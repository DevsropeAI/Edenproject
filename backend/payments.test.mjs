import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Readable } from 'node:stream';
import { createPayments } from './payments.mjs';

test('checkout uses the server price and rejects bookings owned by another account', async () => {
  let order;
  const stripe = { checkout: { sessions: { create: async (payload, options) => {
    assert.equal(payload.line_items[0].price_data.unit_amount, 5085);
    assert.equal(payload.metadata.edenPayment, order.id);
    assert.equal(options.idempotencyKey, order.id + ':initial');
    return { id: 'cs_test', url: 'https://checkout.stripe.com/test' };
  } } } };
  const payments = createPayments(stripe, 'test-secret', 'https://eden.example/return');
  const first = async (sql, id, user) => {
    if (sql.includes('FROM bookings')) return user === 'owner' ? { details: { total: 50.85 } } : undefined;
    return order;
  };
  const run = async (sql, id, booking, customer, kind, amount) => {
    if (sql.startsWith('INSERT')) order = { id, kind, amount_cents: amount, status: 'pending' };
  };
  const result = await payments.customerAction({ id: 'owner', role: 'customer' }, 10, { action: 'pay', amountCents: 1 }, run, first);
  assert.equal(result.url, 'https://checkout.stripe.com/test');
  await assert.rejects(() => payments.customerAction({ id: 'other', role: 'customer' }, 10, { action: 'pay' }, run, first), { status: 404 });
});

test('webhooks only mark matching verified checkout amounts paid', async () => {
  const updates = [];
  const stripe = { webhooks: { constructEvent: (payload, signature) => {
    if (signature !== 'valid') throw new Error('Bad signature');
    return JSON.parse(payload);
  } } };
  const payments = createPayments(stripe, 'test-secret', 'https://eden.example/return');
  function request(signature, amount) {
    const req = Readable.from([Buffer.from(JSON.stringify({ type: 'checkout.session.completed', data: { object: {
      id: 'cs_test', metadata: { edenPayment: 'order' }, payment_status: 'paid', currency: 'cad',
      amount_total: amount, payment_intent: 'pi_test',
    } } }))]);
    req.headers = { 'stripe-signature': signature };
    return req;
  }
  const first = async () => ({ amount_cents: 5085 });
  const run = async (...args) => updates.push(args);
  await assert.rejects(() => payments.webhook(request('invalid', 5085), run, first), { status: 400 });
  await payments.webhook(request('valid', 5000), run, first);
  assert.equal(updates.length, 0);
  await payments.webhook(request('valid', 5085), run, first);
  assert.deepEqual(updates[0].slice(1), ['pi_test', 'cs_test', 'order']);
});
