import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

export const sessionCookie = 'eden_admin_session';
export const sessionSeconds = 8 * 60 * 60;
const digest = value => createHash('sha256').update(value).digest();
const equal = (a, b) => timingSafeEqual(digest(a), digest(b));

export function validPassword(password) {
  const expected = process.env.EDEN_ADMIN_PASSWORD;
  return Boolean(expected) && typeof password === 'string' && equal(password, expected);
}

function signature(expiry) {
  return createHmac('sha256', process.env.EDEN_ADMIN_KEY)
    .update(expiry + ':' + process.env.EDEN_ADMIN_PASSWORD).digest('hex');
}

export function createSession() {
  const expiry = String(Date.now() + sessionSeconds * 1000);
  return expiry + '.' + signature(expiry);
}

export function validSession(value) {
  if (!value || !process.env.EDEN_ADMIN_KEY || !process.env.EDEN_ADMIN_PASSWORD) return false;
  const [expiry, mac, extra] = value.split('.');
  return !extra && /^\d+$/.test(expiry) && Number(expiry) > Date.now() &&
    Boolean(mac) && equal(mac, signature(expiry));
}
