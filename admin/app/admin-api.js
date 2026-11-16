import 'server-only';

export async function adminRequest(path, options) {
  if (!process.env.EDEN_ADMIN_KEY) throw new Error('Set EDEN_ADMIN_KEY for the admin server.');
  const base = process.env.EDEN_API_URL || 'http://127.0.0.1:3001/api';
  const response = await fetch(base + '/admin' + path, {
    ...options,
    cache: 'no-store',
    headers: {
      Authorization: 'Bearer ' + process.env.EDEN_ADMIN_KEY,
      'Content-Type': 'application/json',
    },
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.message);
  return data;
}
