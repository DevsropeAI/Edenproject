import { randomUUID } from 'node:crypto';

function fail(status, message) {
  throw Object.assign(new Error(message), { status });
}

export function createPayments(stripe, webhookSecret, returnUrl) {
  if (new URL(returnUrl).protocol !== 'https:') throw new Error('Use an HTTPS payment return URL.');

  async function customerAction(user, bookingId, body, run, first) {
    if (user.role !== 'customer') fail(403, 'Switch to customer mode.');
    const booking = await first("SELECT details FROM bookings WHERE id = ? AND customer_id = ? AND status = 'completed'", bookingId, user.id);
    if (!booking) fail(404, 'Completed booking unavailable.');
    if (body.action === 'refund') {
      const result = await run("UPDATE payment_orders SET status = 'refund_requested' WHERE booking_id = ? AND kind = 'service' AND status = 'paid'", bookingId);
      if (!result.affectedRows) fail(409, 'Refund request is unavailable.');
      return { requested: true };
    }
    const kind = body.action === 'pay' ? 'service' : body.action === 'tip' ? 'tip' : null;
    if (!kind) fail(400, 'Choose a valid payment action.');
    if (kind === 'tip' && (!Number.isInteger(body.amountCents) || ![500, 1000, 1500].includes(body.amountCents) ||
      !await first("SELECT id FROM payment_orders WHERE booking_id = ? AND kind = 'service' AND status IN ('paid', 'refund_declined')", bookingId))) {
      fail(400, 'Choose a supported tip after paying for the booking.');
    }
    const details = typeof booking.details === 'string' ? JSON.parse(booking.details) : booking.details;
    const amount = kind === 'tip' ? body.amountCents : Math.round(details.total * 100);
    await run('INSERT IGNORE INTO payment_orders (id, booking_id, customer_id, kind, amount_cents) VALUES (?, ?, ?, ?, ?)',
      randomUUID(), bookingId, user.id, kind, amount);
    const record = await first('SELECT * FROM payment_orders WHERE booking_id = ? AND kind = ?', bookingId, kind);
    if (!record || record.status !== 'pending') fail(409, 'This payment already went through.');
    if (kind === 'tip' && record.amount_cents !== amount) fail(409, 'Continue checkout with your originally selected tip amount.');
    if (record.stripe_session) {
      const existing = await stripe.checkout.sessions.retrieve(record.stripe_session);
      if (existing.status === 'open' && existing.url) return { url: existing.url };
      if (existing.status !== 'expired') fail(409, 'Payment confirmation is pending.');
    }
    const session = await stripe.checkout.sessions.create({
      mode: 'payment', payment_method_types: ['card'], success_url: returnUrl, cancel_url: returnUrl,
      metadata: { edenPayment: record.id },
      line_items: [{
        quantity: 1,
        price_data: { currency: 'cad', unit_amount: record.amount_cents, product_data: { name: 'Eden ' + kind + ' #' + bookingId } },
      }],
    }, { idempotencyKey: record.id + ':' + (record.stripe_session ?? 'initial') });
    await run("UPDATE payment_orders SET stripe_session = ? WHERE id = ? AND status = 'pending'", session.id, record.id);
    return { url: session.url };
  }

  async function webhook(req, run, first) {
    let size = 0;
    const chunks = [];
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 1_000_000) fail(413, 'Webhook is too large.');
      chunks.push(chunk);
    }
    let event;
    try {
      event = stripe.webhooks.constructEvent(Buffer.concat(chunks), req.headers['stripe-signature'], webhookSecret);
    } catch {
      fail(400, 'Invalid webhook signature.');
    }
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      const id = session.metadata?.edenPayment;
      if (typeof id !== 'string' || session.payment_status !== 'paid' || session.currency !== 'cad') return { received: true };
      const order = await first('SELECT amount_cents FROM payment_orders WHERE id = ?', id);
      if (order?.amount_cents === session.amount_total && typeof session.payment_intent === 'string') {
        await run("UPDATE payment_orders SET status = 'paid', stripe_intent = ?, stripe_session = ? WHERE id = ? AND status = 'pending'",
          session.payment_intent, session.id, id);
      }
    }
    if (['refund.created', 'refund.updated', 'refund.failed'].includes(event.type)) {
      const refund = event.data.object;
      const id = refund.metadata?.edenPayment;
      const state = refund.status === 'succeeded' ? 'refunded'
        : ['failed', 'canceled'].includes(refund.status) ? 'refund_failed' : null;
      if (state && typeof id === 'string' && typeof refund.payment_intent === 'string') {
        await run("UPDATE payment_orders SET status = ? WHERE id = ? AND stripe_intent = ? AND status = 'refund_processing'",
          state, id, refund.payment_intent);
      }
    }
    return { received: true };
  }

  async function reviewRefund(id, decision, run, first) {
    if (!['Approve refund', 'Decline refund'].includes(decision)) fail(400, 'Choose a refund decision.');
    if (decision === 'Decline refund') {
      const result = await run("UPDATE payment_orders SET status = 'refund_declined' WHERE id = ? AND status = 'refund_requested'", id);
      if (!result.affectedRows) fail(409, 'Refund request is unavailable.');
      return { status: 'refund_declined' };
    }
    await run("UPDATE payment_orders SET status = 'refund_processing' WHERE id = ? AND status = 'refund_requested'", id);
    const record = await first("SELECT stripe_intent FROM payment_orders WHERE id = ? AND status = 'refund_processing'", id);
    if (!record?.stripe_intent) fail(409, 'Refund request is unavailable.');
    const refund = await stripe.refunds.create({ payment_intent: record.stripe_intent, metadata: { edenPayment: id } }, { idempotencyKey: 'eden-refund:' + id });
    if (refund.status === 'succeeded') await run("UPDATE payment_orders SET status = 'refunded' WHERE id = ?", id);
    if (['failed', 'canceled'].includes(refund.status)) await run("UPDATE payment_orders SET status = 'refund_failed' WHERE id = ?", id);
    return { status: refund.status };
  }

  return {
    customerAction, webhook, reviewRefund,
    list: (user, run) => run('SELECT booking_id AS bookingId, kind, amount_cents AS amountCents, status FROM payment_orders WHERE customer_id = ?', user.id),
    adminList: run => run(`SELECT id, CONCAT('Booking #', booking_id) AS title,
      CONCAT(kind, ' · CAD ', FORMAT(amount_cents / 100, 2)) AS detail, status FROM payment_orders`),
  };
}
