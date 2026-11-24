import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { parseEnv } from 'node:util';

// Export exactly one browser-restricted map key. Never export the environment.
const envFile = new URL('../backend/.env', import.meta.url);
const env = existsSync(envFile) ? parseEnv(readFileSync(envFile, 'utf8')) : {};
const key = process.env.EDEN_GOOGLE_MAPS_WEB_KEY ?? env.EDEN_GOOGLE_MAPS_WEB_KEY ?? env.eden_map_api;
if (!key || !/^AIza[\w-]+$/.test(key)) {
  throw new Error('Set EDEN_GOOGLE_MAPS_WEB_KEY or eden_map_api to a website-restricted Maps JavaScript API key.');
}
writeFileSync(new URL('../web/google_maps_config.js', import.meta.url),
  '// Generated browser map configuration. Do not commit.\nwindow.EDEN_GOOGLE_MAPS_API_KEY = ' + JSON.stringify(key) + ';\n');
const adminFile = new URL('../admin/.env.local', import.meta.url);
const current = existsSync(adminFile) ? readFileSync(adminFile, 'utf8') : '';
const entry = 'EDEN_GOOGLE_MAPS_WEB_KEY=' + JSON.stringify(key);
const updated = /^EDEN_GOOGLE_MAPS_WEB_KEY\s*=.*$/m.test(current)
  ? current.replace(/^EDEN_GOOGLE_MAPS_WEB_KEY\s*=.*$/m, () => entry)
  : current.trimEnd() + '\n' + entry + '\n';
writeFileSync(adminFile, updated);
console.log('Browser Maps configuration created for Flutter web and admin (Git ignored). No OAuth credentials exported.');
