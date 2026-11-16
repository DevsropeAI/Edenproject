'use server';

import { redirect } from 'next/navigation';
import { cookies } from 'next/headers';
import { sessionCookie, validSession } from '../admin-auth';
import { adminRequest } from './admin-api';

export async function updateStatus(section, search, formData) {
  if (!validSession((await cookies()).get(sessionCookie)?.value)) {
    throw new Error('Admin sign-in required.');
  }
  const { type, id, status, price } = Object.fromEntries(formData);
  const formats = {
    accounts: /^[a-f0-9]{64}$/, support: /^[a-f0-9]{64}$/, orders: /^\d+$/,
    services: /^(snow|lawn|cleaning)$/, verification: /^[a-f0-9]{64}$/,
    payments: /^[a-f0-9-]{36}$/,
  };
  if (!Object.hasOwn(formats, type) || typeof id !== 'string' || !formats[type].test(id)) {
    throw new Error('Invalid record.');
  }
  const priceCents = type === 'services' ? Math.round(Number(price) * 100) : undefined;
  const query = new URLSearchParams({ section, search });
  try {
    await adminRequest('/' + type + '/' + id, { method: 'POST', body: JSON.stringify({ status, priceCents }) });
    query.set('result', 'saved');
  } catch (error) {
    console.error(error);
    query.set('result', 'error');
  }
  redirect('/?' + query);
}

export async function loadDocument(id, kind) {
  if (!validSession((await cookies()).get(sessionCookie)?.value)) {
    throw new Error('Admin sign-in required.');
  }
  if (typeof id !== 'string' || !/^[a-f0-9]{64}$/.test(id) || !['identification', 'insurance'].includes(kind)) {
    throw new Error('Invalid document.');
  }
  return adminRequest('/verification/' + id + '/' + kind);
}
