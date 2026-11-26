import { browserMapConfig } from '../backend/browser-map-config.mjs';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { parseEnv } from 'node:util';

// Export exactly one browser-restricted map key. Never export the environment.
const envFile = new URL('../backend/.env', import.meta.url);
const env = existsSync(envFile) ? parseEnv(readFileSync(envFile, 'utf8')) : {};
const { key } = browserMapConfig({ ...env, ...process.env });
if (!key) {
  throw new Error('Set eden_map_api (or EDEN_GOOGLE_MAPS_WEB_KEY) in backend/.env to a website-restricted Maps JavaScript API key.');
}
writeFileSync(new URL('../web/google_maps_config.js', import.meta.url),
  '// Generated browser map configuration. Do not commit.\nwindow.EDEN_GOOGLE_MAPS_API_KEY = ' + JSON.stringify(key) + ';\n');
console.log('Flutter browser Maps configuration created (Git ignored). Admin reads Maps configuration from the backend; no admin environment copy is needed.');
