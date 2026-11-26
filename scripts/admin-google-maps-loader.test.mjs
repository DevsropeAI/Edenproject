import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';

const source=readFileSync(new URL('../admin/app/google-map-sdk.mjs',import.meta.url),'utf8').replace(/^import .*;\r?\n/,'').replaceAll('export function','function')+'\nglobalThis.sdk={loadGoogleMaps,mapsErrorMessage};';
function setup() {
  const scripts=[];const timers=new Map();let counter=0;let blocked=false;
  const window={};
  const context={window,URL,mapDiagnostic:()=>{},setTimeout:callback=>{const id=++counter;timers.set(id,callback);return id;},clearTimeout:id=>timers.delete(id),document:{createElement:()=>({dataset:{},remove(){this.removed=true;}}),head:{append(script){if(blocked)throw new Error('blocked');scripts.push(script);}}}};
  runInNewContext(source,context);
  return {...context,scripts,timers,block:()=>{blocked=true;},unblock:()=>{blocked=false;},ready:()=>{window.google={maps:{Map(){},marker:{AdvancedMarkerElement(){}}}};}};
}

test('missing key rejects immediately without inserting a script',async()=>{
  const t=setup();
  await assert.rejects(t.sdk.loadGoogleMaps(undefined),{code:'MAPS_KEY_MISSING'});
  assert.equal(t.scripts.length,0);
  assert.match(t.sdk.mapsErrorMessage({code:'MAPS_KEY_MISSING'}),/running admin configuration/);
});
test('effect loader injects exactly one browser SDK script and resolves its callback',async()=>{
  const t=setup();
  const promise=t.sdk.loadGoogleMaps('browser-test-key');
  assert.equal(t.sdk.loadGoogleMaps('browser-test-key'),promise);
  assert.equal(t.scripts.length,1);
  assert.equal(t.scripts[0].id,'eden-admin-google-maps-sdk');
  const url=new URL(t.scripts[0].src);
  assert.equal(url.origin,'https://maps.googleapis.com');
  assert.equal(url.searchParams.get('key'),'browser-test-key');
  assert.equal(url.searchParams.get('libraries'),'marker');
  assert.equal(url.searchParams.has('CLIENT_SECRET'),false);
  t.ready();t.window.__edenAdminGoogleMapsLoaded();
  assert.equal(await promise,t.window.google.maps);
  assert.equal(t.timers.size,0);
  await t.sdk.loadGoogleMaps();
  assert.equal(t.scripts.length,1);
});
test('invalid SDK callback rejects rather than hanging after clearing the timer',async()=>{
  const t=setup();
  const promise=t.sdk.loadGoogleMaps('browser-test-key');
  t.window.__edenAdminGoogleMapsLoaded();
  await assert.rejects(promise,{code:'MAPS_SDK_UNAVAILABLE'});
  assert.equal(t.timers.size,0);
  assert.equal(t.scripts[0].removed,true);
  const retry=t.sdk.loadGoogleMaps('browser-test-key');
  t.ready();t.window.__edenAdminGoogleMapsLoaded();await retry;
  assert.equal(t.scripts.length,2);
});
test('script network errors can be retried',async()=>{
  const t=setup();const promise=t.sdk.loadGoogleMaps('browser-test-key');
  t.scripts[0].onerror();
  await assert.rejects(promise,{code:'MAPS_NETWORK'});
  const retry=t.sdk.loadGoogleMaps('browser-test-key');
  t.ready();t.window.__edenAdminGoogleMapsLoaded();await retry;
  assert.equal(t.scripts.length,2);
});
test('script insertion failure is retryable and does not leave a cached rejected promise',async()=>{
  const t=setup();t.block();
  await assert.rejects(t.sdk.loadGoogleMaps('browser-test-key'),{code:'MAPS_NETWORK'});
  t.unblock();const retry=t.sdk.loadGoogleMaps('browser-test-key');
  t.ready();t.window.__edenAdminGoogleMapsLoaded();await retry;
  assert.equal(t.scripts.length,1);
});
test('stalled SDK times out and ignores late callbacks safely',async()=>{
  const t=setup();const promise=t.sdk.loadGoogleMaps('browser-test-key');
  const callback=t.window.__edenAdminGoogleMapsLoaded;
  [...t.timers.values()][0]();
  await assert.rejects(promise,{code:'MAPS_TIMEOUT'});
  assert.doesNotThrow(callback);
  assert.equal(t.scripts[0].removed,true);
});
test('initialization messages never echo arbitrary errors or a key',()=>{
  const t=setup();
  assert.equal(t.sdk.mapsErrorMessage(new Error('secret-key-value')).includes('secret-key-value'),false);
});
