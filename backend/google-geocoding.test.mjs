import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createGeocoding } from './geocoding.mjs';

const env = {
  GEOCODING_PROVIDER: 'google', GEOCODING_AUTOCOMPLETE_PROVIDER: 'google',
  GOOGLE_MAPS_SERVER_API_KEY: 'server-test-key',
};
const components = [
  { long_name: '12', types: ['street_number'] },
  { long_name: 'Main Street', types: ['route'] },
  { long_name: 'Lahore Cantt', types: ['sublocality'] },
  { long_name: 'Lahore', types: ['locality'] },
  { long_name: 'Punjab', types: ['administrative_area_level_1'] },
  { long_name: '54000', types: ['postal_code'] },
  { long_name: 'Pakistan', short_name: 'PK', types: ['country'] },
];
const geocode = {
  formatted_address: '12 Main Street, Lahore, Pakistan',
  place_id: 'ChIJTest', address_components: components,
  geometry: { location: { lat: 31.5, lng: 74.3 } },
};
const detail = {
  id: 'ChIJTest', formattedAddress: geocode.formatted_address, types: ['locality'],
  addressComponents: components.map(row => ({ longText: row.long_name, shortText: row.short_name, types: row.types })),
  location: { latitude: 31.5, longitude: 74.3 },
};
const json = value => ({ ok: true, json: async () => value });
const params = value => new URLSearchParams(value);

test('Google lookup requires a server key, never falls back to the browser key, and exposes no secrets', () => {
  const missing = createGeocoding({ GEOCODING_PROVIDER: 'google', eden_map_api: 'browser-key' });
  assert.equal(missing.capabilities.search, false);
  const configured = createGeocoding(env);
  assert.equal(configured.capabilities.search, true);
  assert.equal(configured.capabilities.autocomplete, true);
  assert.equal(configured.capabilities.attribution, 'Google Maps');
  assert.equal(JSON.stringify(configured.capabilities).includes(env.GOOGLE_MAPS_SERVER_API_KEY), false);
});

test('Google address search maps existing fields, preserves the matching city, and does not use the legacy cache', async () => {
  let requests = 0;
  const geo = createGeocoding(env, async url => {
    requests++;
    assert.equal(url.hostname, 'maps.googleapis.com');
    assert.equal(url.searchParams.get('address'), 'Main Street, Lahore');
    assert.equal(url.searchParams.get('components'), 'country:PK');
    return json({ status: 'OK', results: [geocode] });
  });
  const input = params({ q: 'Main Street, Lahore', country: 'PK' });
  const [value] = await geo.lookup('search', input, 'customer');
  assert.equal(value.street, '12 Main Street');
  assert.equal(value.city, 'Lahore');
  assert.equal(value.countryCode, 'PK');
  assert.equal(value.latitude, 31.5);
  await geo.lookup('search', input, 'customer');
  assert.equal(requests, 2);
});

test('Google reverse lookup and zero results retain existing endpoint response shapes', async () => {
  const geo = createGeocoding(env, async url => {
    assert.equal(url.searchParams.get('latlng'), '31.5,74.3');
    return json({ status: 'OK', results: [geocode] });
  });
  assert.equal((await geo.lookup('reverse', params({ lat: '31.5', lng: '74.3' }), 'customer')).city, 'Lahore');
  const empty = createGeocoding(env, async () => json({ status: 'ZERO_RESULTS' }));
  assert.equal(await empty.lookup('reverse', params({ lat: '31', lng: '74' }), 'customer'), null);
  assert.deepEqual(await empty.lookup('search', params({ q: 'Unknown' }), 'customer'), []);
});

test('autocomplete returns predictions in one request and restricts registration/profile suggestions to cities', async () => {
  let requests = 0;
  const geo = createGeocoding(env, async (url, options) => {
    requests++;
    assert.equal(url, 'https://places.googleapis.com/v1/places:autocomplete');
    assert.equal(options.method, 'POST');
    assert.equal(options.headers['X-Goog-Api-Key'], 'server-test-key');
    assert.deepEqual(JSON.parse(options.body), {
      input: 'Lahore', languageCode: 'en', includedRegionCodes: ['pk'],
      includedPrimaryTypes: ['(cities)'], sessionToken: 'test-session',
    });
    return json({ suggestions: [{ placePrediction: { placeId: 'ChIJTest', text: { text: 'Lahore, Pakistan' } } }] });
  });
  const values = await geo.lookup('autocomplete', params({ q: 'Lahore', type: 'city', country: 'PK', sessionToken: 'test-session' }), 'contractor');
  assert.equal(requests, 1);
  assert.deepEqual(values, [{ label: 'Lahore, Pakistan', placeId: 'ChIJTest', needsDetails: true }]);
});

test('only selecting a prediction resolves its address/coordinates and completes its session', async () => {
  const geo = createGeocoding(env, async (url, options) => {
    assert.equal(url.pathname, '/v1/places/ChIJTest');
    assert.equal(url.searchParams.get('sessionToken'), 'test-session');
    assert.equal(options.headers['X-Goog-FieldMask'], 'id,formattedAddress,addressComponents,location,types');
    return json(detail);
  });
  const value = await geo.lookup('place', params({ placeId: 'ChIJTest', type: 'city', sessionToken: 'test-session' }), 'contractor');
  assert.equal(value.city, 'Lahore');
  assert.equal(value.street, '12 Main Street');
  assert.equal(value.longitude, 74.3);
});

test('city details reject a business/address result and malformed IDs are rejected before calling Google', async () => {
  let requests = 0;
  const geo = createGeocoding(env, async () => { requests++; return json({ ...detail, types: ['street_address'] }); });
  await assert.rejects(geo.lookup('place', params({ placeId: '../private' }), 'contractor'), error => error.status === 400);
  assert.equal(requests, 0);
  await assert.rejects(geo.lookup('place', params({ placeId: 'ChIJTest', type: 'city' }), 'registration'), error => error.status === 400);
});

test('denied keys, HTTP failures and network errors fail safely without exposing secrets or switching providers', async () => {
  for (const fetcher of [
    async () => json({ status: 'REQUEST_DENIED', error_message: 'server-test-key' }),
    async () => ({ ok: false, status: 403 }),
    async () => { throw new Error('https://maps.googleapis.com/?key=server-test-key'); },
  ]) {
    const geo = createGeocoding({ ...env, GEOCODING_CONTACT_EMAIL: 'test@example.com' }, fetcher);
    await assert.rejects(geo.lookup('search', params({ q: 'Lahore' }), 'customer'), error =>
      error.status === 503 && !error.message.includes('server-test-key'));
  }
});

test('city search does not misclassify a state as a work city', async () => {
  const geo = createGeocoding(env, async () => json({ status: 'OK', results: [{
    ...geocode, address_components: components.filter(row => !row.types.includes('locality')),
  }] }));
  assert.deepEqual(await geo.lookup('search', params({ q: 'Punjab', type: 'city' }), 'contractor'), []);
});
