import assert from 'node:assert/strict';
import { test } from 'node:test';
import { marketplace } from './marketplace.mjs';

const property = {
  id: 1, details: { name: 'Home', address: '123 Maple Street', size: 'Large', notes: 'Gate code', type: 'House' },
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
    method: 'GET', path: '/api/bookings', user: { id: 'contractor', role: 'contractor' },
    run: async () => [{
      id: 10, status: 'searching', version: 0, contractor_id: null,
      details: { property: { id: 1, ...property.details }, referencePhoto: 'image', notes: 'Private' },
    }],
  });
  assert.equal(offer.property.address, 'Address shared after acceptance');
  assert.equal(offer.property.notes, '');
  assert.equal(offer.referencePhoto, null);
});

test('a stale job acceptance fails when another worker changed the row', async () => {
  const request = {
    method: 'POST', path: '/api/bookings/10', user: { id: 'contractor', role: 'contractor' },
    read: async () => ({ action: 'accept' }),
    first: async sql => sql.startsWith('SELECT * FROM bookings')
      ? { status: 'searching', version: 2, customer_id: 'owner', details: {} }
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
