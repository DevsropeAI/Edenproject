import { signIn } from './sign-in';

export default async function Login({ searchParams }) {
  const { error } = await searchParams;
  return (
    <main>
      <section className="records">
        <h1>Eden Admin</h1>
        <form action={signIn} className="record-actions">
          <label>Username <input name="username" autoComplete="username" required /></label>
          <label>Password <input name="password" type="password" autoComplete="current-password" required /></label>
          <button type="submit">Sign in</button>
        </form>
        {error && <p role="alert">{error === 'config' ? 'Set the admin key and password before signing in.' : 'Incorrect username or password.'}</p>}
      </section>
    </main>
  );
}
