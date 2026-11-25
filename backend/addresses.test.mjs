import assert from 'node:assert/strict';
import { test } from 'node:test';
import { marketplace } from './marketplace.mjs';
import { structuredAddress, propertyMeasurements } from './addresses.mjs';
import { createGeocoding } from './geocoding.mjs';

const customer = { id: 'owner', role: 'customer' };
const contractor = { id: 'worker', role: 'contractor', service: 'Snow removal', area: 'Other legacy area', city_id: 7 };
const details = {
  service: 'snow', notes: 'Private note', referencePhoto: 'private-image', messages: [],
  property: {
    id: 4, name: 'Home', address: '12 Main St, Lahore, Punjab, 54000, Pakistan',
    type: 'House', size: 'Large', notes: 'Private gate', photo: 'private-photo',
    pin: { latitude: 31, longitude: 74 }, cityId: 7,
    structuredAddress: { street: '12 Main St', city: 'Lahore', state: 'Punjab', country: 'Pakistan', postalCode: '54000' },
    measurements: { driveway: 'large', frontYard: true, frontYardSize: '300 sq ft', walkway: 'long' },
  },
};

test('eligible unaccepted contractor receives approved location, instructions and measurements but no photos', async () => {
  const offers = await marketplace({
    method: 'GET', path: '/api/bookings', user: contractor, addressStore: {},
    run: async () => [{ id: 10, status: 'searching', version: 0, contractor_id: null, details }],
  });
  assert.equal(offers.length, 1);
  const property = offers[0].property;
  assert.deepEqual(Object.keys(property).sort(), ['id', 'name', 'address', 'type', 'size', 'notes', 'photo', 'pin', 'measurements'].sort());
  assert.equal(property.photo, null);
  assert.deepEqual(property.pin, details.property.pin);
  assert.equal(property.address, details.property.address);
  assert.equal(property.notes, details.property.notes);
  assert.equal(offers[0].notes, details.notes);
  assert.deepEqual(property.measurements, details.property.measurements);
  assert.equal(offers[0].referencePhoto, null);
  for (const secret of ['street', 'postalCode', 'structuredAddress', 'cityId']) {
    assert.equal(JSON.stringify(offers).includes('"' + secret + '"'), false);
  }
});

test('public offers cross city boundaries while saved address fields remain intact', async () => {
  const request = {
    method: 'GET', path: '/api/bookings', addressStore: {},
    run: async () => [{ id: 10, status: 'searching', contractor_id: null, details }],
  };
  assert.equal((await marketplace({ ...request, user: contractor })).length, 1);
  assert.equal((await marketplace({ ...request, user: { ...contractor, area: 'Lahore', city_id: 8 } })).length, 1);
  const legacyDetails = { ...details, property: { ...details.property, cityId: null } };
  assert.equal((await marketplace({
    ...request, user: { ...contractor, area: 'Lahore' },
    run: async () => [{ id: 10, status: 'searching', contractor_id: null, details: legacyDetails }],
  })).length, 1);
});

test('exact locations remain restricted to eligible offers and the admin-assigned contractor', async () => {
  const rows = [
    { id: 1, dispatch_status: 'pending_admin' },
    { id: 2, dispatch_status: 'assigned', assigned_contractor_id: 'someone-else' },
    { id: 3, dispatch_status: 'assigned', assigned_contractor_id: contractor.id },
    { id: 4, dispatch_status: 'open' },
    { id: 5, dispatch_status: 'open', customer_id: contractor.id },
  ].map(row => ({ status: 'searching', contractor_id: null, details: { ...details, propertyOverrides: { notes: 'Private gate' } }, ...row }));
  const offers = await marketplace({
    method: 'GET', path: '/api/bookings', user: contractor, addressStore: {}, run: async () => rows,
  });
  assert.deepEqual(offers.map(row => row.id), [1, 3, 4]);
  for (const offer of offers) {
    assert.deepEqual(offer.property.pin, details.property.pin);
    assert.equal(offer.property.photo, null);
    assert.equal(offer.notes, details.notes);
    assert.equal(offer.propertyOverrides, undefined);
  }
});

test('customer and accepted contractor retain full property information', async () => {
  for (const user of [customer, contractor]) {
    const [record] = await marketplace({
      method: 'GET', path: '/api/bookings', user, addressStore: {},
      run: async () => [{ id: 10, status: 'accepted', contractor_id: contractor.id, details }],
    });
    assert.equal(record.property.structuredAddress.city, 'Lahore');
    assert.equal(record.property.measurements.walkway, 'long');
  }
});

test('address and measurements reject invalid values while preserving legacy data', () => {
  assert.deepEqual(structuredAddress({}, undefined), {});
  assert.throws(() => structuredAddress({ structuredAddress: { street: 'Main St', city: '', country: 'Pakistan' } }));
  assert.throws(() => propertyMeasurements({ walkway: 'infinite' }));
  assert.throws(() => propertyMeasurements({ frontYard: 'yes' }));
});

test('capabilities require configuration and Nominatim never offers autocomplete', async () => {
  const geo = createGeocoding({ GEOCODING_PROVIDER: 'nominatim', GEOCODING_CONTACT_EMAIL: 'dev@example.com' });
  assert.equal(geo.capabilities.search, true);
  assert.equal(geo.capabilities.autocomplete, false);
  await assert.rejects(() => geo.lookup('autocomplete', new URLSearchParams({ q: 'Lahore' }), 'customer'), error => error.status === 503);
  await assert.rejects(() => geo.lookup('search', new URLSearchParams({ q: 'ab' }), 'customer'), error => error.status === 400);
  await assert.rejects(() => geo.lookup('reverse', new URLSearchParams({ lat: '999', lng: '74' }), 'customer'), error => error.status === 400);
  assert.equal(createGeocoding({}).capabilities.search, false);
});

test('Nominatim search is cached, identifies the app and maps address components', async () => {
  let requests = 0;
  const geo = createGeocoding({
    GEOCODING_PROVIDER: 'nominatim', GEOCODING_CONTACT_EMAIL: 'dev@example.com',
  }, async (url, options) => {
    requests++;
    assert.equal(url.hostname, 'nominatim.openstreetmap.org');
    assert.ok(options.headers['User-Agent'].includes('dev@example.com'));
    return { ok: true, json: async () => [{
      display_name: 'Lahore, Pakistan', lat: '31.5', lon: '74.3',
      address: { city: 'Lahore', state: 'Punjab', country: 'Pakistan', country_code: 'pk' },
    }] };
  });
  const query = new URLSearchParams({ q: 'Lahore' });
  assert.equal((await geo.lookup('search', query, 'customer'))[0].city, 'Lahore');
  await geo.lookup('search', query, 'customer');
  assert.equal(requests, 1);
});

test('structured property save preserves legacy JSON and stores the combined address with the city second', async () => {
  let stored;
  const result = await marketplace({
    method: 'POST', path: '/api/properties', user: customer,
    read: async () => ({
      id: 4, name: 'Home', address: 'Old address', size: 'Large', notes: '',
      type: 'House', photo: null, pin: { latitude: 31.5, longitude: 74.3 },
      structuredAddress: details.property.structuredAddress,
      measurements: { driveway: 'small', walkway: 'long', frontYard: true, frontYardSize: '50 sq ft' },
    }),
    first: async () => ({ id: 4, city_id: null, details: { legacyCustomField: 'preserved' } }),
    addressStore: { city: async () => 7 },
    run: async (sql, json, cityId) => {
      assert.ok(sql.startsWith('UPDATE properties SET details'));
      assert.equal(cityId, 7);
      stored = JSON.parse(json);
      return { affectedRows: 1 };
    },
  });
  assert.equal(result.id, 4);
  assert.equal(stored.legacyCustomField, 'preserved');
  assert.equal(stored.address, '12 Main St, Lahore, Punjab, 54000, Pakistan');
  assert.equal(stored.address.split(',')[1].trim(), 'Lahore');
  assert.equal(stored.measurements.walkway, 'long');
  assert.equal(stored.measurements.backyard, false);
});

test('legacy property create remains available without applying migrations', async () => {
  let stored;
  await marketplace({
    method: 'POST', path: '/api/properties', user: customer,
    read: async () => ({
      name: 'Home', address: 'Old free text', size: 'Standard', notes: '',
      type: 'House', photo: null, pin: null,
    }),
    run: async (sql, owner, json) => {
      assert.equal(sql, 'INSERT INTO properties (owner, details) VALUES (?, ?)');
      stored = JSON.parse(json);
      return { insertId: 4 };
    },
  });
  assert.equal(stored.address, 'Old free text');
});

test('hosted autocomplete uses only the configured adapter and hides the key from capabilities', async () => {
  const geo = createGeocoding({
    GEOCODING_AUTOCOMPLETE_PROVIDER: 'geoapify', GEOAPIFY_API_KEY: 'secret-test-key',
  }, async url => {
    assert.equal(url.hostname, 'api.geoapify.com');
    assert.ok(url.pathname.endsWith('/autocomplete'));
    assert.equal(url.searchParams.get('apiKey'), 'secret-test-key');
    return { ok: true, json: async () => ({ results: [{
      formatted: 'Lahore, Pakistan', city: 'Lahore', country: 'Pakistan', lat: 31, lon: 74,
    }] }) };
  });
  assert.equal(geo.capabilities.autocomplete, true);
  assert.equal(JSON.stringify(geo.capabilities).includes('secret-test-key'), false);
  assert.equal((await geo.lookup('autocomplete', new URLSearchParams({ q: 'Lahore' }), 'user'))[0].city, 'Lahore');
});

test('work city search requests city results and excludes state-only results', async () => {
  const geo = createGeocoding({
    GEOCODING_PROVIDER: 'nominatim', GEOCODING_CONTACT_EMAIL: 'dev@example.com',
  }, async url => {
    assert.equal(url.searchParams.get('featureType'), 'city');
    return { ok: true, json: async () => [
      { display_name: 'Texas, United States', lat: '31', lon: '-99', address: { state: 'Texas', country: 'United States' } },
      { display_name: 'Houston, Texas, United States', lat: '29.7', lon: '-95.4', address: { city: 'Houston', state: 'Texas', country: 'United States' } },
    ] };
  });
  const results = await geo.lookup('search', new URLSearchParams({ q: 'Houston', type: 'city' }), 'worker');
  assert.equal(results.length, 1);
  assert.equal(results[0].city, 'Houston');
  assert.equal(results[0].country, 'United States');
});
