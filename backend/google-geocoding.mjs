const fail = (status, message) => { throw Object.assign(new Error(message), { status }); };

function normalize(row, places = false) {
  const components = row[places ? 'addressComponents' : 'address_components'] ?? [];
  const component = (type, short = false) => {
    const part = components.find(value => value.types?.includes(type));
    return part?.[places ? (short ? 'shortText' : 'longText') : (short ? 'short_name' : 'long_name')] ?? '';
  };
  const point = places ? row.location : row.geometry?.location;
  return {
    label: (places ? row.formattedAddress : row.formatted_address) ?? '',
    street: [component('street_number'), component('route')].filter(Boolean).join(' '),
    // Never turn a neighbourhood/sublocality into a different matching city.
    city: component('locality') || component('postal_town') || component('administrative_area_level_3'),
    state: component('administrative_area_level_1'),
    postalCode: [component('postal_code'), component('postal_code_suffix')].filter(Boolean).join('-'),
    country: component('country'), countryCode: component('country', true),
    latitude: places ? point?.latitude : point?.lat,
    longitude: places ? point?.longitude : point?.lng,
    placeId: (places ? row.id : row.place_id) ?? '',
  };
}

export class GoogleGeocodingProvider extends GeocodingProvider {
  constructor(key, fetcher = fetch) { super(); this.key = key; this.fetcher = fetcher; }

  async response(url, options = {}) {
    const response = await this.fetcher(url, { ...options, signal: AbortSignal.timeout(8000) });
    if (!response.ok) {
      if (response.status === 429) fail(503, 'Google address lookup has reached its limit. Enter the address manually or try again later.');
      // Do not return Google's raw error or the request URL: either may contain credentials.
      fail(503, 'Google address lookup is unavailable. Check the server key, enabled APIs and billing. Manual entry is available.');
    }
    return response.json();
  }

  async geocode(parameters) {
    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
    url.searchParams.set('key', this.key);
    url.searchParams.set('language', 'en');
    for (const [key, value] of Object.entries(parameters)) if (value) url.searchParams.set(key, value);
    const body = await this.response(url);
    if (body.status === 'ZERO_RESULTS') return [];
    if (body.status !== 'OK') fail(503, 'Google address lookup is unavailable. Check the server key, enabled APIs and billing. Manual entry is available.');
    return (body.results ?? []).map(row => normalize(row));
  }

  search(q, country) {
    return this.geocode({ address: q, components: country ? 'country:' + country : '' });
  }

  async reverse(lat, lng) {
    return (await this.geocode({ latlng: `${lat},${lng}` }))[0] ?? null;
  }

  async autocomplete(q, country, type, sessionToken) {
    const body = await this.response('https://places.googleapis.com/v1/places:autocomplete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': this.key },
      body: JSON.stringify({
        input: q, languageCode: 'en',
        ...(country ? { includedRegionCodes: [country.toLowerCase()] } : {}),
        ...(type === 'city' ? { includedPrimaryTypes: ['(cities)'] } : {}),
        ...(sessionToken ? { sessionToken } : {}),
      }),
    });
    // Resolve only the chosen prediction, never prefetch details for the whole list.
    return (body.suggestions ?? []).flatMap(({ placePrediction: place }) => place?.placeId ? [{
      label: place.text?.text ?? '', placeId: place.placeId, needsDetails: true,
    }] : []);
  }

  async place(placeId, type, sessionToken) {
    const url = new URL('https://places.googleapis.com/v1/places/' + encodeURIComponent(placeId));
    url.searchParams.set('languageCode', 'en');
    if (sessionToken) url.searchParams.set('sessionToken', sessionToken);
    const row = await this.response(url, {
      headers: {
        'X-Goog-Api-Key': this.key,
        'X-Goog-FieldMask': 'id,formattedAddress,addressComponents,location,types',
      },
    });
    const result = normalize(row, true);
    if (type === 'city' && (!result.city || !result.country ||
      !row.types?.some(value => ['locality', 'postal_town', 'administrative_area_level_3'].includes(value)))) {
      fail(400, 'Choose a city result, not a street or business.');
    }
    if (!Number.isFinite(result.latitude) || !Number.isFinite(result.longitude)) {
      fail(503, 'Google did not return a location for this result. Try another result or enter the address manually.');
    }
    return result;
  }
}
import { GeocodingProvider } from './geocoding-provider.mjs';

