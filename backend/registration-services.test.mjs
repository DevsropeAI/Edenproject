import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createApi } from './server.mjs';

const catalog = [{ id: 'snow', title: 'Snow Removal' }, { id: 'lawn', title: 'Lawn Mowing' },
  { id: 'tree', title: 'Tree Trimming' }, { id: 'paver', title: 'Paver Installation' }];
const account = { name: 'Contractor', email: 'test@example.com', password: 'test-password',
  phone: '1234567890', role: 'contractor', area: 'Lahore', service: 'Tree Trimming', serviceIds: ['lawn', 'paver'] };

async function register(body, { pricing = true, unavailable, failInsert = false } = {}) {
  const events = []; const inserted = [];
  const db = {
    execute: async (sql, args) => {
      if (sql.includes('FROM services')) return [catalog];
      if (sql.includes('INSERT INTO users')) { inserted.push(args); return [{ affectedRows: 1 }]; }
      throw new Error('Unexpected database query');
    },
    getConnection: async () => ({
      beginTransaction: async () => events.push('begin'),
      execute: async (sql, args) => {
        if (sql.includes('FROM services')) { events.push('check:' + args[0]); return [args[0] === unavailable ? [] : [{ id: args[0] }]]; }
        if (sql.startsWith('SELECT id, active FROM cities')) return [[{ id: 7, active: 1 }]];
        if (sql.includes('INSERT INTO users')) { events.push('user'); inserted.push(args); }
        if (sql.includes('INSERT INTO contractor_services')) {
          events.push('service:' + args[1]);
          if (failInsert) throw new Error('Simulated write failure');
          assert.equal(args[0], inserted[0][0]);
        }
        return [{ affectedRows: 1 }];
      },
      commit: async () => events.push('commit'), rollback: async () => events.push('rollback'), release: () => events.push('release'),
    }),
  };
  const api = createApi({ db, servicesPricing: pricing, structuredAddresses: true });
  const response = await new Promise(resolve => api.emit('request', {
    method: 'POST', url: '/api/auth/register', headers: {}, socket: { remoteAddress: '127.0.0.1' },
    async *[Symbol.asyncIterator]() { yield Buffer.from(JSON.stringify(body)); },
  }, {
    setHeader() {}, writeHead(status) { this.status = status; return this; },
    end(raw) { resolve({ status: this.status, body: JSON.parse(raw) }); },
  }));
  return { ...response, events, inserted };
}

test('registration saves a new primary and multiple additional services atomically', async () => {
  const result = await register(account);
  assert.equal(result.status, 200);
  assert.equal(result.inserted[0][9], 'Tree Trimming');
  assert.deepEqual(result.events, ['begin', 'check:lawn', 'check:paver', 'user', 'service:lawn', 'service:paver', 'commit', 'release']);
});

test('registration preserves selected work city alongside additional services', async () => {
  const result = await register({ ...account, workCity: { city: 'Lahore', state: 'Punjab', country: 'Pakistan' } });
  assert.equal(result.status, 200);
  assert.equal(result.inserted[0][10], 7);
  assert.ok(result.events.includes('service:lawn'));
});

test('invalid, duplicate, unavailable and customer service selections are rejected', async () => {
  for (const body of [{ ...account, serviceIds: ['missing'] }, { ...account, serviceIds: ['lawn', 'lawn'] },
    { ...account, serviceIds: 'lawn' }, { ...account, role: 'customer' }, { ...account, service: 'Unsupported Service' }]) {
    const result = await register(body);
    assert.equal(result.status, 400);
    assert.equal(result.inserted.length, 0);
  }
});

test('a service disabled during registration rolls back before creating the account', async () => {
  const result = await register(account, { unavailable: 'paver' });
  assert.equal(result.status, 400);
  assert.equal(result.inserted.length, 0);
  assert.deepEqual(result.events.slice(-2), ['rollback', 'release']);
});

test('a failed additional-service insert rolls back the account and never commits', async () => {
  const result = await register(account, { failInsert: true });
  assert.equal(result.status, 500);
  assert.equal(result.events.includes('commit'), false);
  assert.deepEqual(result.events.slice(-2), ['rollback', 'release']);
});

test('legacy single-primary registration stays available without the pricing migration', async () => {
  const result = await register({ ...account, service: 'Snow removal', serviceIds: [] }, { pricing: false });
  assert.equal(result.status, 200);
  assert.equal(result.events.length, 0);
  const multiple = await register({ ...account, service: 'Snow removal' }, { pricing: false });
  assert.equal(multiple.status, 503);
});
