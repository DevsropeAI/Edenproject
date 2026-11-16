import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createPhoneVerification } from './phone-verification.mjs';

test('SMS verification requires provider approval', async () => {
  const calls = [];
  const service = createPhoneVerification({
    TWILIO_VERIFY_SERVICE_SID: 'VA' + 'a'.repeat(32),
    TWILIO_API_KEY: 'test-key',
    TWILIO_API_SECRET: 'test-secret',
  }, async (url, options) => {
    calls.push({ url, fields: Object.fromEntries(options.body) });
    return Response.json({ status: options.body.get('Code') === '123456' ? 'approved' : 'pending' });
  });

  await service.send('+14165550100');
  assert.deepEqual(calls[0].fields, { To: '+14165550100', Channel: 'sms' });
  assert.match(calls[0].url, /\/Verifications$/);
  assert.equal(await service.check('+14165550100', '000000'), false);
  assert.equal(await service.check('+14165550100', '123456'), true);
  assert.match(calls[2].url, /\/VerificationCheck$/);
});
