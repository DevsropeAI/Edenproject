// Browser-restricted Maps keys are intended for the Maps JavaScript client.
// Explicitly whitelist these settings; never return server keys or OAuth values.
export function browserMapConfig(env = process.env) {
  const configured = [env.EDEN_GOOGLE_MAPS_WEB_KEY, env.eden_map_api]
    .find(value => typeof value === 'string' && value.trim());
  const key = configured?.trim() ?? '';
  const mapId = typeof env.EDEN_GOOGLE_MAPS_MAP_ID === 'string'
    ? env.EDEN_GOOGLE_MAPS_MAP_ID.trim() : '';
  return {
    key: /^AIza[\w-]+$/.test(key) ? key : '',
    mapId: mapId || 'DEMO_MAP_ID',
  };
}
