import assert from 'node:assert/strict';
import { test } from 'node:test';
import { marketplace } from './marketplace.mjs';

const path = '/api/bookings/42/location';
const customer = { id: 'customer', role: 'customer' };
const contractor = { id: 'contractor', role: 'contractor' };

test('GPS updates are constrained to the assigned en-route booking', async () => {
  const request = {
    path, method: 'POST', user: contractor,
    read: async () => ({ latitude: 43.65, longitude: -79.38 }),
    run: async (sql, latitude, longitude, timestamp, id, owner) => {
      assert.match(sql, /contractor_id = \? AND status = 'enRoute'/);
      assert.deepEqual([latitude, longitude, id, owner], [43.65, -79.38, 42, contractor.id]);
      assert.ok(timestamp > 0);
      return { affectedRows: 1 };
    },
  };
  assert.deepEqual(await marketplace(request), { shared: true });
  await assert.rejects(() => marketplace({ ...request, run: async () => ({ affectedRows: 0 }) }), { status: 409 });
  await assert.rejects(() => marketplace({ ...request, read: async () => ({ latitude: 95, longitude: 0 }) }), { status: 400 });
  await assert.rejects(() => marketplace({ ...request, user: customer }), { status: 403 });
});

test('customers only receive fresh locations for their own en-route bookings', async () => {
  const point = { latitude: 43.65, longitude: -79.38, sharedAt: Date.now() };
  const request = {
    path, method: 'GET', user: customer,
    first: async (sql, cutoff, id, owner) => {
      assert.match(sql, /l.shared_at >= \?/);
      assert.deepEqual([id, owner], [42, customer.id]);
      assert.ok(cutoff <= Date.now() - 30_000);
      return { status: 'enRoute', ...point };
    },
  };
  assert.deepEqual(await marketplace(request), { location: point });
  assert.deepEqual(await marketplace({ ...request, first: async () => ({ status: 'arrived', ...point }) }), { location: null });
  assert.deepEqual(await marketplace({ ...request, first: async () => ({ status: 'enRoute', sharedAt: null }) }), { location: null });
  await assert.rejects(() => marketplace({ ...request, first: async () => undefined }), { status: 404 });
});
