import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mapDiagnostic,mapFailureDetails,watchMapBrowserFailures} from '../admin/app/map-diagnostics.mjs';

test('diagnostics whitelist fields and redact credentials and URL queries',()=>{
  const original=console.error;const output=[];
  console.error=(...args)=>output.push(args);
  try {
    mapDiagnostic('error','test',{keyConfigured:true,customer:{name:'Private Person'},latitude:31.5,key:'private',message:'https://maps.googleapis.com/maps/api/js?key=AIzaFakeTestKey&token=private'});
    const text=JSON.stringify(output);
    assert.equal(text.includes('AIzaFakeTestKey'),false);
    assert.equal(text.includes('Private Person'),false);
    assert.equal(text.includes('31.5'),false);
    assert.equal(text.includes('token=private'),false);
    assert.equal(output[0][1].keyConfigured,true);
    const error=new Error('Private Person at private address');
    error.stack='Error: Private Person\n    at init (https://example.com/app.js?token=private:1:2)';
    const details=JSON.stringify(mapFailureDetails(error));
    assert.equal(details.includes('Private Person'),false);
    assert.equal(details.includes('token=private'),false);
  } finally {console.error=original;}
});

test('Google authentication and CSP failures are reported and listeners cleaned up',()=>{
  const previous=globalThis.window;const original=console.error;
  const listeners=new Map();const codes=[];let previousCalled=0;
  const previousHandler=()=>previousCalled++;
  globalThis.window={location:{origin:'https://admin.example.com'},gm_authFailure:previousHandler,addEventListener:(name,fn)=>listeners.set(name,fn),removeEventListener:(name)=>listeners.delete(name)};
  console.error=()=>{};
  try {
    const cleanup=watchMapBrowserFailures(error=>codes.push(error.code));
    window.gm_authFailure();
    listeners.get('securitypolicyviolation')({blockedURI:'https://maps.googleapis.com/maps/api/js?key=private',effectiveDirective:'script-src'});
    assert.deepEqual(codes,['MAPS_AUTH','MAPS_CSP']);
    assert.equal(previousCalled,1);
    cleanup();assert.equal(window.gm_authFailure,previousHandler);assert.equal(listeners.size,0);
  } finally {globalThis.window=previous;console.error=original;}
});
