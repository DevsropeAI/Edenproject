import { resolveAdminMapConfig } from './map-config.mjs';
import { adminRequest } from './admin-api';
import { Dashboard } from './dashboard';

export const dynamic = 'force-dynamic';

export default async function Page({ searchParams }) {
  try {
    const { section, search, result } = await searchParams;
    const dashboard = await adminRequest('/dashboard');
    const { LargeJobs: _retired, ...catalogDashboard } = dashboard;
    const data = { Map: [], ...catalogDashboard };
    let mapData = null;
    let mapError = false;
    if (section === 'Map') {
      try {
        mapData = await adminRequest('/map');
      } catch (error) {
        console.error(error);
        mapError = true;
      }
    }
    const maps = resolveAdminMapConfig(mapData?.browserMapConfig, process.env);
    return <Dashboard data={data} mapData={mapData} mapError={mapError}
      mapKey={maps.key} mapId={maps.mapId}
      section={typeof section === 'string' && Object.hasOwn(data, section) ? section : 'Customers'}
      result={result}
      search={typeof search === 'string' ? search : ''}
    />;
  } catch (error) {
    console.error(error);
    return <main><h1>Eden Admin</h1><p>Could not load Eden. Check the API connection and server configuration.</p></main>;
  }
}
