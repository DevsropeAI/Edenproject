import assert from 'node:assert/strict';
import { test } from 'node:test';
import { marketplace } from './marketplace.mjs';

const property = {
  id: 1, details: { name: 'Home', address: '123 Maple Street', size: 'Large', notes: 'Gate code', type: 'House' },
};
const contractor = {
  id: 'contractor', role: 'contractor', area: ' toronto ', service: 'Snow removal',
};
const offerDetails = {
  service: 'snow', property: { id: 1, ...property.details, address: '123 Maple Street, Toronto, M5V 1A1' },
  referencePhoto: 'image', notes: 'Private',
};

test('booking creation calculates the server price and uses the customer property', async () => {
  const result = await marketplace({
    method: 'POST', path: '/api/bookings', user: { id: 'owner', role: 'customer' },
    read: async () => ({ propertyId: 1, date: new Date(Date.now() + 86400_000).toISOString(), service: 'snow', notes: '', urgent: true, total: 0 }),
    first: async (sql, id, owner) => {
      if (sql.includes('FROM services')) return { price_cents: 4500 };
      assert.equal(id, 1);
      assert.equal(owner, 'owner');
      return property;
    },
    run: async (sql, customer, details) => {
      assert.equal(customer, 'owner');
      assert.equal(JSON.parse(details).total, 90.4);
      return { insertId: 10 };
    },
  });
  assert.equal(result.id, 10);
  assert.equal(result.status, 'searching');
});

test('unassigned jobs hide exact address and access instructions', async () => {
  const [offer] = await marketplace({
    method: 'GET', path: '/api/bookings', user: contractor,
    run: async () => [{
      id: 10, status: 'searching', version: 0, contractor_id: null,
      details: offerDetails,
    }, {
      id: 11, status: 'searching', version: 0, contractor_id: null,
      details: { ...offerDetails, service: 'cleaning' },
    }],
  });
  assert.equal(offer.property.address.trim(), 'toronto');
  assert.equal(offer.property.notes, '');
  assert.equal(offer.referencePhoto, null);
});

test('a stale job acceptance fails when another worker changed the row', async () => {
  const request = {
    method: 'POST', path: '/api/bookings/10', user: contractor,
    read: async () => ({ action: 'accept' }),
    first: async sql => sql.startsWith('SELECT * FROM bookings')
      ? { status: 'searching', version: 2, customer_id: 'owner', details: offerDetails }
      : sql.includes('FROM contractor_reviews') ? { status: 'Approved' } : undefined,
    run: async (sql, details, status, contractor, id, version) => {
      assert.equal(status, 'accepted');
      assert.equal(contractor, 'contractor');
      assert.equal(id, 10);
      assert.equal(version, 2);
      return { affectedRows: 0 };
    },
  };
  await assert.rejects(() => marketplace(request), error => error.status === 409);
});

test('an available contractor cannot accept a job outside their city', async () => {
  await assert.rejects(() => marketplace({
    method: 'POST', path: '/api/bookings/10', user: { ...contractor, area: 'Ottawa' },
    read: async () => ({ action: 'accept' }),
    first: async sql => sql.startsWith('SELECT * FROM bookings')
      ? { status: 'searching', version: 0, customer_id: 'owner', details: offerDetails }
      : undefined,
    run: async () => assert.fail('ineligible offer was updated'),
  }), error => error.status === 404);
});

test('releasing an accepted job reopens it and removes prior chat from the next offer', async () => {
  const details = { ...offerDetails, messages: [{ text: 'Private chat' }] };
  const released = await marketplace({
    method: 'POST', path: '/api/bookings/10', user: contractor,
    read: async () => ({ action: 'release' }),
    first: async sql => sql.startsWith('SELECT * FROM bookings')
      ? { status: 'accepted', version: 1, customer_id: 'owner', contractor_id: contractor.id, details }
      : undefined,
    run: async (_, saved, status, assignee) => {
      assert.equal(status, 'searching');
      assert.equal(assignee, null);
      assert.deepEqual(JSON.parse(saved).releasedBy, [contractor.id]);
      assert.deepEqual(JSON.parse(saved).messages, []);
      return { affectedRows: 1 };
    },
  });
  assert.equal(released.status, 'searching');
  assert.equal(released.releasedBy, undefined);
});
