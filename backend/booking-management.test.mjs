import assert from 'node:assert/strict';
import { test } from 'node:test';
import { marketplace } from './marketplace.mjs';

const customer = { id: 'owner', role: 'customer' };
const contractor = { id: 'worker', role: 'contractor' };
function request(action, status = 'searching', user = customer, affectedRows = 1) {
  return {
    method: 'POST', path: '/api/bookings/1', user,
    read: async () => ({ action, date: new Date(Date.now() + 86400000).toISOString(), notes: 'Updated instructions' }),
    first: async sql => sql.startsWith('SELECT b.*') ? {
      id: 1, customer_id: 'owner', contractor_id: status === 'searching' ? null : 'worker', status, version: 2,
      details: { property: { address: 'Street, Lahore' }, messages: [], total: 90.4 },
    } : undefined,
    run: async () => ({ affectedRows }),
  };
}
test('customer can edit only their unaccepted booking without changing quote', async () => {
  const result = await marketplace(request('edit'));
  assert.equal(result.notes, 'Updated instructions');
  assert.equal(result.total, 90.4);
  for (const status of ['accepted', 'enRoute', 'working', 'submitted', 'completed']) {
    await assert.rejects(() => marketplace(request('edit', status)), e => e.status === 409);
    await assert.rejects(() => marketplace(request('delete', status)), e => e.status === 409);
  }
});
test('delete closes the offer and hides it from customer lists while retaining its record', async () => {
  const result = await marketplace(request('delete'));
  assert.equal(result.status, 'cancelled');
  assert.equal(result.customerDeleted, true);
  const rows = await marketplace({ method: 'GET', path: '/api/bookings', user: customer,
    run: async () => [{ details: result }] });
  assert.deepEqual(rows, []);
});
test('contractor cancellation reopens the booking only after departure', async () => {
  for (const status of ['enRoute', 'arrived', 'working', 'submitted']) {
    const input = request('cancel', status, contractor);
    input.run = async (_, saved, state, assignee) => {
      const details = JSON.parse(saved);
      assert.equal(state, 'searching');
      assert.equal(assignee, null);
      assert.deepEqual(details.releasedBy, ['worker']);
      assert.equal(details.assignmentHistory[0].contractorId, 'worker');
      assert.equal(details.assignmentHistory[0].status, status);
      assert.deepEqual(details.messages, []);
      assert.equal(details.before, null);
      assert.equal(details.after, null);
      return { affectedRows: 1 };
    };
    const result = await marketplace(input);
    assert.equal(result.status, 'searching');
    assert.equal(result.assignmentHistory, undefined);
    await assert.rejects(() => marketplace(request('cancel', status)), e => e.status === 409);
  }
  for (const status of ['accepted', 'completed', 'cancelled']) {
    await assert.rejects(() => marketplace(request('cancel', status, contractor)), e => e.status === 409);
  }
  await assert.rejects(() => marketplace(request('cancel', 'accepted', { id: 'other', role: 'contractor' })), e => e.status === 404);
});
test('edit and delete reject acceptance races and invalid input', async () => {
  for (const action of ['edit', 'delete']) await assert.rejects(() => marketplace(request(action, 'searching', customer, 0)), e => e.status === 409);
  const invalid = request('edit');
  invalid.read = async () => ({ action: 'edit', date: 'invalid', notes: '' });
  await assert.rejects(() => marketplace(invalid), e => e.status === 400);
});

test('a reopened job excludes the departing contractor, hides prior work, and remains deletable by customer', async () => {
  let saved;
  const input = request('cancel', 'working', contractor);
  input.run = async (_, details) => { saved = JSON.parse(details); return { affectedRows: 1 }; };
  await marketplace(input);
  saved.service = 'snow';
  const row = { id: 1, customer_id: 'owner', contractor_id: null, status: 'searching', version: 3, details: saved };
  const list = user => marketplace({ method: 'GET', path: '/api/bookings', user, run: async () => [row] });
  const workUser = { ...contractor, area: 'Lahore', service: 'Snow removal' };
  assert.deepEqual(await list(workUser), []);
  const [offer] = await list({ ...workUser, id: 'next-worker' });
  assert.equal(offer.status, 'searching');
  assert.equal(offer.assignmentHistory, undefined);
  assert.deepEqual(offer.messages, []);
  assert.equal(offer.before, null);
  const deletion = request('delete');
  deletion.first = async () => row;
  assert.equal((await marketplace(deletion)).customerDeleted, true);
});
