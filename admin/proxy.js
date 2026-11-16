import { NextResponse } from 'next/server';
import { sessionCookie, validSession } from './admin-auth';

export function proxy(request) {
  if (validSession(request.cookies.get(sessionCookie)?.value)) return NextResponse.next();
  if (request.method !== 'GET' || request.nextUrl.pathname !== '/') {
    return new NextResponse('Admin sign-in required.', { status: 401 });
  }
  return NextResponse.redirect(new URL('/login', request.url));
}

export const config = { matcher: ['/'] };
