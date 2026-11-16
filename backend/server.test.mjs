import assert from 'node:assert/strict';
import { once } from 'node:events';
import { test } from 'node:test';
import { createApi } from './server.mjs';
import { openDatabase } from './db.mjs';
import { randomUUID } from 'node:crypto';

const testDatabase = process.env.EDEN_MYSQL_TEST_URL;
test('accounts, role switching, support and admin share persistent state', { skip: !testDatabase }, async t => {
  const domain = randomUUID() + '.test';
  let db;
  let server;
  let base;
  t.after(async () => {
    if (server?.listening) await stop();
    if (db) {
      await db.execute('DELETE FROM users WHERE email LIKE ?', ['%@' + domain]);
      await db.end();
    }
  });

  async function start() {
    db ??= await openDatabase(testDatabase);
    server = createApi({ db, adminKey: 'test-admin-key' });
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    base = 'http://127.0.0.1:' + server.address().port + '/api';
  }
  async function stop() {
    server.close();
    await once(server, 'close');
  }
  async function request(path, { body, token, method = body ? 'POST' : 'GET', status = 200 } = {}) {
    const response = await fetch(base + path, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    const data = await response.json();
    assert.equal(response.status, status, JSON.stringify(data));
    return data;
  }

  await start();
  const credentials = { email: 'customer@' + domain, password: 'test-password-1' };
  const registration = { ...credentials, name: 'Avery', phone: '4165550142', role: 'customer' };
  await request('/auth/login', { body: credentials, status: 401 });
  await request('/auth/register', { body: registration });
  await request('/auth/register', { body: registration, status: 409 });
  const signedIn = await request('/auth/login', { body: credentials });
  assert.equal(signedIn.user.role, 'customer');
  const token = signedIn.token;
  await request('/auth/mode', { token, body: { role: 'contractor' }, status: 400 });
  await request('/auth/mode', { token, body: { role: 'admin' }, status: 400 });
  const switched = await request('/auth/mode', {
    token, body: { role: 'contractor', area: 'Toronto', service: 'Lawn mowing' },
  });
  assert.deepEqual(switched.roles, ['customer', 'contractor']);
  await request('/auth/profile', { token, body: { name: 'Avery Morgan', phone: '4165550111' } });
  await request('/support', { token, body: { description: 'Please review my account.' } });

  await stop();
  await start();
  const restored = await request('/auth/me', { token });
  assert.equal(restored.role, 'contractor');
  assert.equal(restored.name, 'Avery Morgan');
  const ticket = (await request('/support', { token }))[0];
  assert.equal(ticket.status, 'Open');
  assert.equal((await request('/auth/mode', { token, body: { role: 'customer' } })).role, 'customer');
  assert.equal((await request('/auth/mode', { token, body: { role: 'contractor' } })).area, 'Toronto');

  const adminOptions = { token: 'test-admin-key' };
  await request('/admin/dashboard', { token, status: 401 });
  const dashboard = await request('/admin/dashboard', adminOptions);
  assert.equal(dashboard.Customers.find(row => row.id === restored.id)?.id, restored.id);
  assert.equal(dashboard.Contractors.find(row => row.id === restored.id)?.id, restored.id);
  await request('/admin/support/' + ticket.id, { ...adminOptions, body: { status: 'Resolved' } });
  assert.equal((await request('/support', { token }))[0].status, 'Resolved');
  await request('/admin/accounts/' + restored.id, { ...adminOptions, body: { status: 'Blocked' } });
  await request('/auth/me', { token, status: 401 });
  await request('/auth/login', { body: credentials, status: 403 });
  await request('/admin/accounts/' + restored.id, { ...adminOptions, body: { status: 'Active' } });
  await request('/auth/me', { token, status: 401 });

  const contractor = { email: 'contractor@' + domain, password: 'test-password-2' };
  await request('/auth/register', { body: { ...contractor, name: 'Taylor', phone: '4165550119', role: 'contractor', area: 'Toronto', service: 'Snow removal' } });
  const contractorSession = await request('/auth/login', { body: contractor });
  assert.equal(contractorSession.user.role, 'contractor');
  assert.deepEqual(await request('/support', { token: contractorSession.token }), []);
  const customerSession = await request('/auth/login', { body: credentials });
  await request('/auth/mode', { token: customerSession.token, body: { role: 'customer' } });
  const property = await request('/properties', {
    token: customerSession.token,
    body: { name: 'Home', address: '123 Maple St, Toronto, ON', size: 'Large', type: 'House', notes: 'Side gate' },
  });
  const order = await request('/bookings', {
    token: customerSession.token,
    body: { propertyId: property.id, date: new Date(Date.now() + 86400_000).toISOString(), service: 'snow', notes: '', urgent: true },
  });
  assert.equal(order.total, 90.4);
  const contractorOptions = { token: contractorSession.token };
  await request('/bookings/' + order.id, { ...contractorOptions, body: { action: 'accept' }, status: 403 });
  const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jkH0AAAAASUVORK5CYII=';
  for (const kind of ['identification', 'insurance']) {
    await request('/account-images/' + kind, { ...contractorOptions, body: { image: png } });
  }
  await request('/admin/verification/' + contractorSession.user.id, { ...adminOptions, body: { status: 'Approved' } });
  const offers = await request('/bookings', contractorOptions);
  assert.equal(offers.find(job => job.id === order.id)?.property.notes, '');
  await request('/bookings/' + order.id, { ...contractorOptions, body: { action: 'accept' } });
  const tracking = '/bookings/' + order.id + '/location';
  const customerOptions = { token: customerSession.token };
  const point = { latitude: 43.65, longitude: -79.38 };
  await request(tracking, { ...contractorOptions, body: point, status: 409 });
  await request('/bookings/' + order.id, { ...contractorOptions, body: { action: 'advance', status: 'enRoute' } });
  await request(tracking, { ...contractorOptions, body: point });
  const { location } = await request(tracking, customerOptions);
  assert.equal(location.latitude, point.latitude);
  assert.equal(location.longitude, point.longitude);
  await request(tracking, { ...contractorOptions, method: 'DELETE' });
  assert.equal((await request(tracking, customerOptions)).location, null);
  await request('/bookings/' + order.id, { ...contractorOptions, body: { action: 'message', text: 'See you tomorrow.' } });
  assert.equal((await request('/bookings', { token: customerSession.token }))[0].messages[0].text, 'See you tomorrow.');
  await request('/admin/orders/' + order.id, { ...adminOptions, body: { status: 'cancelled' } });
  await db.execute('DELETE FROM bookings WHERE id = ?', [order.id]);
  await request('/auth/logout', { token: contractorSession.token, body: {} });
  await request('/auth/me', { token: contractorSession.token, status: 401 });
  const newSession = await request('/auth/login', { body: contractor });
  await request('/auth/me', { token: newSession.token, method: 'DELETE' });
  await request('/auth/login', { body: contractor, status: 401 });
});
