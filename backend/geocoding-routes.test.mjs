import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createApi } from './server.mjs';

async function request(user, path, method = 'GET', body = {}, overrides = {}) {
  const server = createApi({
    db: {
      execute: async sql => {
        if (sql.includes('FROM sessions')) return [[...(user ? [user] : [])]];
        throw new Error('Unexpected database access');
      },
    },
    geocoding: { capabilities: { search: true, autocomplete: false }, lookup: async () => [{ city: 'Lahore' }] },
    ...overrides,
  });
  const req = {
    method, url: path, headers: { authorization: 'Bearer test-session' },
    socket: { remoteAddress: '127.0.0.1' },
    async *[Symbol.asyncIterator]() { yield Buffer.from(JSON.stringify(body)); },
  };
  return new Promise(resolve => {
    const res = {
      status: 0, setHeader() {},
      writeHead(status) { this.status = status; return this; },
      end(json) { resolve({ status: this.status, body: JSON.parse(json) }); },
    };
    server.emit('request', req, res);
  });
}

test('geocoding endpoints require a signed-in customer or contractor', async () => {
  assert.equal((await request(null, '/api/geo/search?q=Lahore')).status, 401);
  assert.equal((await request({ role: 'other' }, '/api/geo/search?q=Lahore')).status, 403);
  assert.equal((await request({ id: 'owner', role: 'customer' }, '/api/geo/search?q=Lahore')).status, 200);
});

test('contractor registration saves the selected city and account in one transaction', async () => {
  const events = [];
  const response = await request(null, '/api/auth/register', 'POST', {
    name: 'Contractor', email: 'contractor@example.com', password: 'test-password',
    phone: '1234567890', role: 'contractor', area: 'Lahore', service: 'Snow removal',
    workCity: { city: 'Lahore', state: 'Punjab', country: 'Pakistan' },
  }, {
    structuredAddresses: true,
    db: {
      getConnection: async () => ({
        beginTransaction: async () => events.push('begin'),
        execute: async (sql, args) => {
          if (sql.startsWith('SELECT id, active FROM cities')) return [[{ id: 7, active: 1 }]];
          if (sql.includes('INSERT INTO users')) {
            assert.equal(args[8], 'Lahore');
            assert.equal(args[10], 7);
            events.push('user');
          }
          return [{ affectedRows: 1 }];
        },
        commit: async () => events.push('commit'),
        rollback: async () => events.push('rollback'),
        release: () => events.push('release'),
      }),
    },
  });
  assert.equal(response.status, 200);
  assert.deepEqual(events, ['begin', 'user', 'commit', 'release']);
});

test('registration city lookup works before sign-in while general geocoding stays protected', async () => {
  assert.equal((await request(null, '/api/auth/work-city-options')).status, 200);
  const response = await request(null, '/api/auth/work-city-search?q=Lahore');
  assert.equal(response.status, 200);
  assert.equal(response.body[0].city, 'Lahore');
  assert.equal((await request(null, '/api/geo/reverse?lat=31&lng=74')).status, 401);
});

test('work city writes enforce contractor role and migration readiness', async () => {
  assert.equal((await request({ id: 'owner', role: 'customer' }, '/api/contractor/work-location', 'POST')).status, 403);
  assert.equal((await request({ id: 'worker', role: 'contractor' }, '/api/contractor/work-location', 'POST')).status, 503);
});
