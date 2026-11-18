import { signIn } from './sign-in';

export default async function Login({ searchParams }) {
  const { error } = await searchParams;

  return (
    <main className="admin-login">
      <section className="admin-login__card" aria-labelledby="admin-login-title">
        <div className="admin-login__mark" aria-hidden="true">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
            <path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V10Z" />
            <path d="M9 21v-8h6v8" />
          </svg>
        </div>
        <h1 id="admin-login-title">Eden Admin</h1>
        <p className="admin-login__intro">Sign in to manage the marketplace.</p>
        {error && (
          <p className="admin-login__error" role="alert">
            {error === 'config' ? 'Set the admin key and password before signing in.' : 'Incorrect username or password.'}
          </p>
        )}
        <form action={signIn} className="admin-login__form">
          <label>
            Username
            <input name="username" autoComplete="username" autoCapitalize="none" spellCheck={false} required />
          </label>
          <label>
            Password
            <input name="password" type="password" autoComplete="current-password" required />
          </label>
          <button type="submit">Sign in <span aria-hidden="true">→</span></button>
        </form>
      </section>
    </main>
  );
}
