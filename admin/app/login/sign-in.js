'use server';

import { cookies, headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { createSession, sessionCookie, sessionSeconds, validPassword } from '../../admin-auth';

export async function signIn(formData) {
  if (!process.env.EDEN_ADMIN_KEY || !process.env.EDEN_ADMIN_PASSWORD) redirect('/login?error=config');
  if (formData.get('username') !== 'admin' || !validPassword(formData.get('password'))) {
    redirect('/login?error=credentials');
  }
  const requestHeaders = await headers();
  (await cookies()).set(sessionCookie, createSession(), {
    httpOnly: true, sameSite: 'strict', path: '/', maxAge: sessionSeconds,
    secure: requestHeaders.get('x-forwarded-proto') === 'https',
  });
  redirect('/');
}
