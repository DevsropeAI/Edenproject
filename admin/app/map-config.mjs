// Prefer the shared backend setting. Legacy admin environment entries remain a
// fallback so admin/backend can be deployed separately during this update.
export function resolveAdminMapConfig(remote, env = {}) {
  const first = (...values) => values.find(value => typeof value === 'string' && value.trim())?.trim();
  return {
    key: first(remote?.key, env.EDEN_GOOGLE_MAPS_WEB_KEY, env.eden_map_api) ?? '',
    mapId: first(env.EDEN_GOOGLE_MAPS_MAP_ID, remote?.mapId) ?? 'DEMO_MAP_ID',
  };
}
