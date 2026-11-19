import { openDatabase } from './db.mjs';
import { configureDatabase } from './local-setup.mjs';
import { createApi } from './server.mjs';
import { runWeeklyBookings } from './weekly-bookings.mjs';
import nodemailer from 'nodemailer';
import Stripe from 'stripe';
import { createPayments } from './payments.mjs';
import { createPhoneVerification } from './phone-verification.mjs';
import { addressesReady, runAddressMigration } from './migrations/runner.mjs';

const databaseUrl = await configureDatabase();
const { EDEN_SMTP_URL, EDEN_EMAIL_FROM } = process.env;
if (Boolean(EDEN_SMTP_URL) !== Boolean(EDEN_EMAIL_FROM)) {
  throw new Error('Configure both EDEN_SMTP_URL and EDEN_EMAIL_FROM to enable password reset.');
}
const mail = EDEN_SMTP_URL ? nodemailer.createTransport(EDEN_SMTP_URL) : null;

const { STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, EDEN_PAYMENT_RETURN_URL } = process.env;
const paymentConfig = [STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, EDEN_PAYMENT_RETURN_URL];
if (paymentConfig.some(Boolean) && !paymentConfig.every(Boolean)) throw new Error('Configure all Stripe checkout settings.');
const payments = STRIPE_SECRET_KEY ? createPayments(new Stripe(STRIPE_SECRET_KEY), STRIPE_WEBHOOK_SECRET, EDEN_PAYMENT_RETURN_URL) : undefined;

const port = Number(process.env.PORT ?? 3001);
const db = await openDatabase(databaseUrl);
// Enable only after reviewing and approving the migration for this database.
if (process.env.EDEN_APPLY_ADDRESS_MIGRATION === 'true') await runAddressMigration(db);
const structuredAddresses = await addressesReady(db);
const server = createApi({
  db,
  structuredAddresses,
  payments,
  origins: (process.env.EDEN_ORIGINS ?? '').split(',').map(origin => origin.trim()),
  adminKey: process.env.EDEN_ADMIN_KEY,
  phoneVerification: createPhoneVerification(process.env),
  sendPasswordReset: mail ? (email, code) => mail.sendMail({
    from: EDEN_EMAIL_FROM, to: email, subject: 'Reset your Eden password',
    text: 'Enter this code in Eden to choose a new password. The code expires in 20 minutes.\n\n' + code,
  }) : undefined,
}).listen(port, process.env.HOST ?? '0.0.0.0', () => {
  console.log('Eden API listening on port ' + port);
});
if (process.env.EDEN_ENABLE_WEEKLY_ORDERS === 'true') {
  let running = false;
  const tick = async () => {
    if (running) return;
    running = true;
    try {
      await runWeeklyBookings(db);
    } catch (error) {
      console.error('Weekly booking job failed', error.code ?? error.name);
    } finally {
      running = false;
    }
  };
  const interval = setInterval(tick, 60_000);
  server.once('close', () => clearInterval(interval));
  void tick();
}
