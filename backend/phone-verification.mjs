export function createPhoneVerification(env, request = fetch) {
  const { TWILIO_VERIFY_SERVICE_SID, TWILIO_API_KEY, TWILIO_API_SECRET } = env;
  const settings = [TWILIO_VERIFY_SERVICE_SID, TWILIO_API_KEY, TWILIO_API_SECRET];
  if (!settings.some(Boolean)) return undefined;
  if (!settings.every(Boolean) || !/^VA[a-f\d]{32}$/i.test(TWILIO_VERIFY_SERVICE_SID)) {
    throw new Error('Configure the Twilio Verify service SID, API key and secret.');
  }
  const base = 'https://verify.twilio.com/v2/Services/' + TWILIO_VERIFY_SERVICE_SID;
  const authorization = 'Basic ' + Buffer.from(TWILIO_API_KEY + ':' + TWILIO_API_SECRET).toString('base64');
  async function call(path, fields) {
    return request(base + path, {
      method: 'POST', headers: { Authorization: authorization },
      body: new URLSearchParams(fields), signal: AbortSignal.timeout(10000),
    });
  }
  return {
    async send(phone) {
      const response = await call('/Verifications', { To: phone, Channel: 'sms' });
      if (!response.ok) throw Object.assign(new Error('Could not send an SMS code. Check the number or try again later.'), { status: 502 });
    },
    async check(phone, code) {
      const response = await call('/VerificationCheck', { To: phone, Code: code });
      return response.ok && (await response.json()).status === 'approved';
    },
  };
}
