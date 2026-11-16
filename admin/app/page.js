import { adminRequest } from './admin-api';
import { Dashboard } from './dashboard';

export const dynamic = 'force-dynamic';

export default async function Page({ searchParams }) {
  try {
    const { section, search, result } = await searchParams;
    const data = await adminRequest('/dashboard');
    return <Dashboard data={data}
      section={typeof section === 'string' && Object.hasOwn(data, section) ? section : 'Customers'}
      result={result}
      search={typeof search === 'string' ? search : ''}
    />;
  } catch (error) {
    console.error(error);
    return <main><h1>Eden Admin</h1><p>Could not load Eden. Check the API connection and server configuration.</p></main>;
  }
}
