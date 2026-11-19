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
    first: async sql => sql.startsWith('SELECT b.*, p.details')
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
    first: async sql => sql.startsWith('SELECT b.*, p.details')
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
    first: async sql => sql.startsWith('SELECT b.*, p.details')
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

test('contractor milestones persist customer notices with the booking update', async () => {
  for (const [before, after] of [['accepted', 'enRoute'], ['working', 'submitted']]) {
    const result = await marketplace({
      method: 'POST', path: '/api/bookings/10', user: contractor,
      read: async () => ({ action: 'advance', status: after }),
      first: async sql => sql.startsWith('SELECT b.*, p.details')
        ? { status: before, version: 4, customer_id: 'owner', contractor_id: contractor.id,
          details: { ...offerDetails, after: 'photo', customerNotices: [{ status: 'accepted', version: 2 }] } }
        : undefined,
      run: async (_, details, status, assignee, id, expectedVersion) => {
        assert.equal(status, after);
        assert.equal(expectedVersion, 4);
        const notices = JSON.parse(details).customerNotices;
        assert.equal(notices.length, 2);
        assert.equal(notices[1].status, after);
        assert.equal(notices[1].version, 5);
        assert.ok(Number.isFinite(Date.parse(notices[1].at)));
        return { affectedRows: 1 };
      },
    });
    assert.equal(result.customerNotices.at(-1).status, after);
  }
});


test('a property address corrected after booking is used to match an open job', async () => {
  const row = {
    id: 10, status: 'searching', version: 0, contractor_id: null,
    details: { ...offerDetails, property: { ...offerDetails.property, address: 'Gulberg 2' } },
    current_property: { ...offerDetails.property, address: '123 Maple Street, Toronto, ON' },
  };
  const offers = await marketplace({
    method: 'GET', path: '/api/bookings', user: contractor,
    run: async () => [row],
  });
  assert.equal(offers[0].id, row.id);
  assert.equal(offers[0].property.address.trim(), 'toronto');
});

test('chat read positions are persisted per role without marking later messages read', async () => {
  for (const role of ['customer', 'contractor']) {
    const details = {
      ...offerDetails,
      messages: [{ contractor: true, text: 'Hello' }, { contractor: false, text: 'Thanks' }],
      chatRead: { customer: 0, contractor: 0 },
    };
    const result = await marketplace({
      method: 'POST', path: '/api/bookings/10',
      user: role === 'customer' ? { id: 'owner', role } : contractor,
      read: async () => ({ action: 'read', count: 1 }),
      first: async sql => sql.startsWith('SELECT b.*, p.details')
        ? { id: 10, status: 'accepted', version: 3, customer_id: 'owner', contractor_id: contractor.id, details }
        : undefined,
      run: async (_, json) => {
        const saved = JSON.parse(json);
        assert.equal(saved.chatRead[role], 1);
        assert.equal(saved.chatRead[role === 'customer' ? 'contractor' : 'customer'], 0);
        assert.equal(saved.messages.length, 2);
        return { affectedRows: 1 };
      },
    });
    assert.equal(result.chatRead[role], 1);
  }
});

test('chat cannot be marked read beyond the messages delivered to a participant', async () => {
  await assert.rejects(() => marketplace({
    method: 'POST', path: '/api/bookings/10', user: contractor,
    read: async () => ({ action: 'read', count: 99 }),
    first: async sql => sql.startsWith('SELECT b.*, p.details')
      ? { id: 10, status: 'accepted', version: 0, customer_id: 'owner', contractor_id: contractor.id,
          details: { ...offerDetails, messages: [] } }
      : undefined,
    run: async () => assert.fail('Invalid read position was saved'),
  }), error => error.status === 400);
});
