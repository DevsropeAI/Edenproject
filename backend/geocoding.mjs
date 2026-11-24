import { setTimeout as delay } from 'node:timers/promises';
import { GoogleGeocodingProvider } from './google-geocoding.mjs';
import { GeocodingProvider } from './geocoding-provider.mjs';
export { GeocodingProvider } from './geocoding-provider.mjs';

const fail = (status, message) => { throw Object.assign(new Error(message), { status }); };

function normalizeNominatim(row) {
  const a = row.address ?? {};
  return {
    label: row.display_name ?? '',
    street: [a.house_number, a.road ?? a.pedestrian ?? a.residential].filter(Boolean).join(' '),
    city: a.city ?? a.town ?? a.village ?? a.municipality ?? '',
    state: a.state ?? a.province ?? '',
    postalCode: a.postcode ?? '',
    country: a.country ?? '',
    countryCode: a.country_code?.toUpperCase() ?? '',
    latitude: Number(row.lat), longitude: Number(row.lon),
  };
}

export class NominatimProvider extends GeocodingProvider {
  constructor(email, fetcher = fetch) {
    super();
    this.email = email;
    this.fetcher = fetcher;
    this.queue = Promise.resolve();
    this.lastRequest = 0;
    this.pending = 0;
  }

  async request(path, parameters) {
    if (++this.pending > 10) {
      this.pending--;
      fail(429, 'Address search is busy. Try again shortly.');
    }
    const operation = this.queue.then(async () => {
      await delay(Math.max(0, 1100 - (Date.now() - this.lastRequest)));
      this.lastRequest = Date.now();
      const url = new URL(path, 'https://nominatim.openstreetmap.org/');
      for (const [key, value] of Object.entries(parameters)) if (value) url.searchParams.set(key, value);
      const response = await this.fetcher(url, {
        headers: { 'User-Agent': 'EdenMarketplace/1.0 (' + this.email + ')', 'Accept-Language': 'en' },
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) fail(503, 'Address lookup is temporarily unavailable. Manual entry is available.');
      return response.json();
    });
    this.queue = operation.catch(() => {});
    try { return await operation; } finally { this.pending--; }
  }

  async search(q, country, type) {
    return (await this.request('/search', {
      q, countrycodes: country?.toLowerCase(), format: 'jsonv2', addressdetails: '1', limit: '5',
      featureType: type === 'city' ? 'city' : '',
    })).map(normalizeNominatim);
  }

  async reverse(lat, lng) {
    const row = await this.request('/reverse', {
      lat: String(lat), lon: String(lng), format: 'jsonv2', addressdetails: '1',
    });
    return row.error ? null : normalizeNominatim(row);
  }
}

export class GeoapifyProvider extends GeocodingProvider {
  constructor(key, fetcher = fetch) { super(); this.key = key; this.fetcher = fetcher; }
  async request(kind, parameters) {
    const url = new URL('https://api.geoapify.com/v1/geocode/' + kind);
    url.searchParams.set('apiKey', this.key);
    url.searchParams.set('format', 'json');
    url.searchParams.set('lang', 'en');
    for (const [name, value] of Object.entries(parameters)) if (value) url.searchParams.set(name, value);
    const response = await this.fetcher(url, { signal: AbortSignal.timeout(8000) });
    if (!response.ok) fail(503, 'Address lookup is temporarily unavailable. Manual entry is available.');
    const body = await response.json();
    return (body.results ?? []).map(a => ({
      label: a.formatted ?? '',
      street: [a.housenumber, a.street].filter(Boolean).join(' '),
      city: a.city ?? a.town ?? a.village ?? '',
      state: a.state ?? '', postalCode: a.postcode ?? '', country: a.country ?? '',
      countryCode: a.country_code?.toUpperCase() ?? '', latitude: a.lat, longitude: a.lon,
    }));
  }
  search(q, country, type) { return this.request('search', { text: q, limit: '5', type: type === 'city' ? 'city' : '', filter: country ? 'countrycode:' + country.toLowerCase() : '' }); }
  autocomplete(q, country, type) { return this.request('autocomplete', { text: q, limit: '5', type: type === 'city' ? 'city' : '', filter: country ? 'countrycode:' + country.toLowerCase() : '' }); }
  async reverse(lat, lng) { return (await this.request('reverse', { lat: String(lat), lon: String(lng) }))[0] ?? null; }
}

export function createGeocoding(env = process.env, fetcher = fetch) {
  const nominatim = env.GEOCODING_CONTACT_EMAIL && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(env.GEOCODING_CONTACT_EMAIL)
    ? new NominatimProvider(env.GEOCODING_CONTACT_EMAIL, fetcher) : null;
  const geoapify = env.GEOAPIFY_API_KEY ? new GeoapifyProvider(env.GEOAPIFY_API_KEY, fetcher) : null;
  const google = env.GOOGLE_MAPS_SERVER_API_KEY ? new GoogleGeocodingProvider(env.GOOGLE_MAPS_SERVER_API_KEY, fetcher) : null;
  const provider = env.GEOCODING_PROVIDER === 'nominatim' ? nominatim :
    env.GEOCODING_PROVIDER === 'geoapify' ? geoapify :
    env.GEOCODING_PROVIDER === 'google' ? google : null;
  const autocomplete = env.GEOCODING_AUTOCOMPLETE_PROVIDER === 'geoapify' ? geoapify :
    env.GEOCODING_AUTOCOMPLETE_PROVIDER === 'google' ? google : null;
  const cache = new Map();
  const inFlight = new Map();
  const limits = new Map();

  return {
    capabilities: {
      search: Boolean(provider), reverse: Boolean(provider), autocomplete: Boolean(autocomplete),
      attribution: provider instanceof GoogleGeocodingProvider || autocomplete instanceof GoogleGeocodingProvider ? 'Google Maps' :
        provider instanceof NominatimProvider ? '© OpenStreetMap contributors' :
        provider || autocomplete ? 'Powered by Geoapify · © OpenStreetMap contributors' : '',
    },
    async lookup(kind, params, account) {
      const now = Date.now();
      for (const [key, value] of limits) if (value.until <= now) limits.delete(key);
      const limit = limits.get(account) ?? { count: 0, until: now + 60_000 };
      limits.set(account, limit);
      if (++limit.count > 20) fail(429, 'Too many address requests. Try again in a minute.');
      const q = params.get('q')?.trim();
      const country = params.get('country')?.trim() ?? '';
      const type = params.get('type') ?? '';
      const sessionToken = params.get('sessionToken') ?? '';
      const placeId = params.get('placeId') ?? '';
      if (sessionToken && !/^[A-Za-z0-9_-]{1,36}$/.test(sessionToken)) fail(400, 'Invalid address search session.');
      if (kind === 'place' && !/^[A-Za-z0-9_-]{1,512}$/.test(placeId)) fail(400, 'Choose a valid address result.');
      if (type && type !== 'city') fail(400, 'Choose a valid place type.');
      if (!['reverse', 'place'].includes(kind) && (!q || q.length < 3 || q.length > 250)) fail(400, 'Enter between 3 and 250 characters.');
      if (country && !/^[A-Za-z]{2}$/.test(country)) fail(400, 'Country filter must be a two-letter code.');
      const lat = Number(params.get('lat')), lng = Number(params.get('lng'));
      if (kind === 'reverse' && (!params.get('lat') || !params.get('lng') || !Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180)) {
        fail(400, 'Choose valid coordinates.');
      }
      const selected = ['autocomplete', 'place'].includes(kind) ? autocomplete : provider;
      if (!selected) fail(503, 'Address lookup is not configured. You can enter the address manually.');
      if (kind === 'place' && !(selected instanceof GoogleGeocodingProvider)) fail(503, 'Address details are unavailable. Search again or enter the address manually.');
      // Google content is fetched on demand, not placed in the legacy result cache.
      if (selected instanceof GoogleGeocodingProvider) {
        try {
          const value = kind === 'reverse' ? await selected.reverse(lat, lng) :
            kind === 'place' ? await selected.place(placeId, type, sessionToken) :
            await selected[kind](q, country, type, sessionToken);
          return kind === 'search' && type === 'city' ? value.filter(row => row.city && row.country) : value;
        } catch (error) {
          if (error.status) throw error;
          fail(503, 'Google address lookup is temporarily unavailable. You can enter the address manually.');
        }
      }
      const key = JSON.stringify([kind, q?.toLowerCase(), country.toUpperCase(), type, kind === 'reverse' ? [lat, lng] : null]);
      const saved = cache.get(key);
      if (saved && saved.until > now) return saved.value;
      if (inFlight.has(key)) return inFlight.get(key);
      const request = (async () => {
      try {
        const results = kind === 'reverse' ? await selected.reverse(lat, lng) : await selected[kind](q, country, type);
        const value = kind !== 'reverse' && type === 'city'
          ? results.filter(result => result.city && result.country) : results;
        if (cache.size >= 500) cache.delete(cache.keys().next().value);
        cache.set(key, { value, until: now + 300_000 });
        return value;
      } catch (error) {
        if (error.status) throw error;
        fail(503, 'Address lookup is temporarily unavailable. You can enter the address manually.');
      } finally {
        inFlight.delete(key);
      }
      })();
      inFlight.set(key, request);
      return request;
    },
  };
}

