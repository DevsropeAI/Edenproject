import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(new URL('../web/google_maps_loader.js', import.meta.url), 'utf8');
function setup(key) {
  const scripts = [];
  const timers = new Map();
  const logs=[];
  const window = { EDEN_GOOGLE_MAPS_API_KEY: key };
  runInNewContext(source, {
    window, URL, console:{info:(...args)=>logs.push(args),error:(...args)=>logs.push(args)},
    setTimeout: fn => { timers.set(1, fn); return 1; },
    clearTimeout: id => timers.delete(id),
    document: {
      createElement: () => ({ remove() { this.removed = true; } }),
      head: { append: script => scripts.push(script) },
    },
  });
  return { window, scripts, timers, logs };
}

test('web diagnostic logs never include the browser key',async()=>{
  const t=setup('private-browser-test-key');
  const promise=t.window.edenLoadGoogleMaps();
  t.scripts[0].onerror();await assert.rejects(promise);
  t.window.gm_authFailure();
  assert.equal(JSON.stringify(t.logs).includes('private-browser-test-key'),false);
  assert.match(JSON.stringify(t.logs),/google-auth-failure/);
});

test('missing key leaves the app usable without making a Google request', async () => {
  const { window, scripts } = setup();
  await assert.rejects(window.edenLoadGoogleMaps(), /not configured/);
  assert.equal(scripts.length, 0);
});

test('multiple maps share one SDK load and retain only the browser key in its URL', async () => {
  const { window, scripts, timers } = setup('browser-test-key');
  const first = window.edenLoadGoogleMaps();
  assert.equal(first, window.edenLoadGoogleMaps());
  assert.equal(scripts.length, 1);
  const url = new URL(scripts[0].src);
  assert.equal(url.origin, 'https://maps.googleapis.com');
  assert.equal(url.searchParams.get('key'), 'browser-test-key');
  assert.equal(url.searchParams.has('CLIENT_SECRET'), false);
  window.google = { maps: { Map() {} } };
  window.__edenGoogleMapsLoaded();
  await first;
  await window.edenLoadGoogleMaps();
  assert.equal(scripts.length, 1);
  assert.equal(timers.size, 0);
});

test('a failed SDK load can be retried without reloading the app', async () => {
  const { window, scripts } = setup('browser-test-key');
  const first = window.edenLoadGoogleMaps();
  scripts[0].onerror();
  await assert.rejects(first, /could not load/);
  assert.equal(scripts[0].removed, true);
  const retry = window.edenLoadGoogleMaps();
  assert.equal(scripts.length, 2);
  window.__edenGoogleMapsLoaded();
  await retry;
});

test('a stalled request times out rather than leaving the map loading forever', async () => {
  const { window, scripts, timers } = setup('browser-test-key');
  const first = window.edenLoadGoogleMaps();
  timers.get(1)();
  await assert.rejects(first, /timed out/);
  assert.equal(scripts[0].removed, true);
});
