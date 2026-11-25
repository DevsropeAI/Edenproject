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

test('dashboard retires category dispatch while retaining the map and compatibility key', async () => {
  const response = await request('/api/admin/dashboard', async sql => {
    assert.doesNotMatch(sql, /dispatch_status = 'pending_admin'/);
    return [[]];
  }, { largeJobsDispatch: true });
  assert.equal(response.status, 200);
  assert.deepEqual(response.body.LargeJobs, []);
  assert.ok(Object.hasOwn(response.body, 'Map'));
});

test('admin map remains available without pricing enabled and still requires admin authentication', async () => {
  const execute = async () => [[]];
  const response = await request('/api/admin/map', execute);
  assert.equal(response.status, 200);
  assert.deepEqual(response.body.markers, []);
  assert.equal((await request('/api/admin/map', execute, {}, 'incorrect')).status, 401);
});

test('long-term admin queue is driven by booking arrangement, not service category', async () => {
  const response=await request('/api/admin/dashboard',async sql=>{
    if(sql.includes('u.name AS customer_name')){
      assert.match(sql,/bookingType/);
      assert.doesNotMatch(sql,/service_category/);
      return [[{id:9,dispatch_status:'pending_admin',customer_name:'Customer',customer_email:'customer@example.test',details:{bookingType:'long_term',service:'custom',serviceTitle:'Window Cleaning',property:{address:'Street, City',measurements:{walkway:'long'}},total:84.75,scheduledDate:'2026-12-01',notes:'Instructions'}}]];
    }
    return [[]];
  },{servicesPricing:true,largeJobsDispatch:true});
  assert.equal(response.status,200);
  assert.equal(response.body.LongTermJobs[0].title,'Window Cleaning #9');
  assert.equal(response.body.LongTermJobs[0].notes,'Instructions');
  assert.deepEqual(response.body.LargeJobs,[]);
});
