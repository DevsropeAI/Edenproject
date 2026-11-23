import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createApi } from './server.mjs';

async function request(path, execute, options = {}, token = 'test-admin') {
  const server = createApi({ db: { execute }, adminKey: 'test-admin', ...options });
  return new Promise(resolve => server.emit('request', {
    method: 'GET', url: path, headers: { authorization: `Bearer ${token}` },
    socket: { remoteAddress: '127.0.0.1' },
  }, {
    setHeader() {}, writeHead(status) { this.status = status; return this; },
    end(value) { resolve({ status: this.status, body: JSON.parse(value) }); },
  }));
}

test('pending large jobs load without a nonexistent bookings timestamp column', async () => {
  const response = await request('/api/admin/dashboard', async sql => {
    if (sql.includes('FROM bookings b')) {
      assert.doesNotMatch(sql, /created_at/);
      assert.match(sql, /b.status = 'searching'/);
      return [[{ id: 30, service: 'drivewayBuild', total: 100, cityId: '7', address: 'Example address', dispatch_status: 'pending_admin' }]];
    }
    return [[]];
  }, { largeJobsDispatch: true });
  assert.equal(response.status, 200);
  assert.equal(response.body.LargeJobs[0].id, '30');
  assert.equal(response.body.LargeJobs[0].cityId, 7);
  assert.ok(Object.hasOwn(response.body, 'Map'));
});

test('admin map remains available without pricing enabled and still requires admin authentication', async () => {
  const execute = async () => [[]];
  const response = await request('/api/admin/map', execute);
  assert.equal(response.status, 200);
  assert.deepEqual(response.body.markers, []);
  assert.equal((await request('/api/admin/map', execute, {}, 'incorrect')).status, 401);
});

test('large-job database failures are reported instead of becoming a false empty list', async () => {
  const response = await request('/api/admin/dashboard', async sql => {
    if (sql.includes('FROM bookings b')) throw new Error('Database unavailable');
    return [[]];
  }, { largeJobsDispatch: true });
  assert.equal(response.status, 500);
});
