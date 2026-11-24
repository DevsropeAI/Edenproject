import assert from 'node:assert/strict';
import { test } from 'node:test';
import { marketplace } from './marketplace.mjs';

const stored = {
  id: 1, customer_id: 'owner', contractor_id: 'worker', status: 'enRoute', version: 8,
  details: { service: 'snow', property: { id: 1, address: 'Main St, Lahore', notes: '' }, messages: [],
    customerNotices: [{ status: 'accepted', version: 3 }, { status: 'enRoute', version: 7 }], customerNoticeReadVersion: 0 },
};
function request(version, { user = { id: 'owner', role: 'customer' }, row = stored, run = async () => ({ affectedRows: 1 }) } = {}) {
  return marketplace({ method: 'POST', path: '/api/bookings/1', user, read: async () => ({ action: 'read-updates', version }),
    first: async sql => sql.startsWith('SELECT b.*') ? structuredClone(row) : undefined, run });
}

test('the owner acknowledges only the viewed update and cannot clear a newer update', async () => {
  const result = await request(3, { run: async (sql, version, id, owner, expectedVersion) => {
    assert.ok(sql.includes('JSON_SET'));
    assert.deepEqual([version, id, owner, expectedVersion], [3, 1, 'owner', 8]);
    return { affectedRows: 1 };
  } });
  assert.equal(result.customerNoticeReadVersion, 3);
  assert.equal(result.customerNotices.at(-1).version, 7);
  assert.equal(result.status, 'enRoute');
  assert.equal(result.version, 9);
  assert.equal(stored.details.customerNoticeReadVersion, 0);
});

test('another customer or contractor cannot acknowledge the owner progress updates', async () => {
  for (const user of [{ id: 'other', role: 'customer' }, { id: 'worker', role: 'contractor', service: 'Snow removal', area: 'Lahore' }]) {
    await assert.rejects(request(7, { user, run: async () => assert.fail('unauthorized read wrote data') }), error => error.status === 404);
  }
});

test('future, negative, fractional and nonnumeric acknowledgement positions are rejected', async () => {
  for (const version of [9, -1, 2.5, '7', null]) {
    await assert.rejects(request(version), error => error.status === 400);
  }
});

test('completed/cancelled updates remain readable and older acknowledgements never regress read state', async () => {
  assert.equal((await request(7, { row: { ...stored, status: 'cancelled' } })).customerNoticeReadVersion, 7);
  const row = { ...stored, details: { ...stored.details, customerNoticeReadVersion: 7 } };
  const result = await request(3, { row, run: async () => assert.fail('already-read update wrote data') });
  assert.equal(result.customerNoticeReadVersion, 7);
  assert.equal(result.version, 8);
});

test('an acknowledgement fails safely on a concurrent booking change', async () => {
  await assert.rejects(request(7, { run: async () => ({ affectedRows: 0 }) }), error => error.status === 409);
});

test('arrival, start, submission, completion, release and contractor cancellation create progress notices', async () => {
  for (const [before, after, action, role] of [
    ['enRoute', 'arrived', 'advance', 'contractor'], ['arrived', 'working', 'advance', 'contractor'],
    ['working', 'submitted', 'advance', 'contractor'], ['submitted', 'completed', 'advance', 'customer'],
    ['accepted', 'searching', 'release', 'contractor'], ['enRoute', 'searching', 'cancel', 'contractor'],
  ]) {
    const result = await marketplace({
      method: 'POST', path: '/api/bookings/1', user: { id: role === 'customer' ? 'owner' : 'worker', role },
      read: async () => ({ action, status: after }),
      first: async sql => sql.startsWith('SELECT b.*') ? {
        ...structuredClone(stored), status: before, details: { ...structuredClone(stored.details), before: 'photo', after: 'photo' },
      } : undefined,
      run: async () => ({ affectedRows: 1 }),
    });
    assert.equal(result.status, after);
    assert.equal(result.customerNotices.at(-1).status, after);
    assert.equal(result.customerNotices.at(-1).version, 9);
  }
});
