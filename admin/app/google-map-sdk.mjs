import {mapDiagnostic} from './map-diagnostics.mjs';
let pending;
const failure = (code, message) => Object.assign(new Error(message), { code });
const ready = () => window.google?.maps?.Map && window.google?.maps?.marker?.AdvancedMarkerElement;

export function mapsErrorMessage(error) {
  const messages = {
    MAPS_AUTH: 'Google rejected Maps authentication. Check the Google Console error, API key restrictions, API activation and billing.',
    MAPS_CSP: 'The admin site content-security policy blocked Google Maps. Check the browser Console and hosting security headers.',
    MAPS_KEY_MISSING: 'Google Maps key is missing from the running admin configuration. Set EDEN_GOOGLE_MAPS_WEB_KEY on the admin server and restart it.',
    MAPS_NETWORK: 'Google Maps script was blocked or could not be downloaded. Check browser Network errors, content-security policy and extensions.',
    MAPS_TIMEOUT: 'Google Maps did not finish loading. Check the Maps JavaScript request in browser Network, then retry.',
    MAPS_SDK_UNAVAILABLE: 'Google Maps downloaded but its map libraries are unavailable. Check the Google error in the browser Console and API key restrictions.',
    MAPS_BROWSER_REQUIRED: 'Google Maps must be initialized in the browser.',
  };
  return messages[error?.code] ?? 'The map could not initialize. Check the Google Maps error in the browser Console, then retry.';
}

export function loadGoogleMaps(key) {
  if (typeof window === 'undefined') return Promise.reject(failure('MAPS_BROWSER_REQUIRED', 'Maps require a browser.'));
  if (ready()) {mapDiagnostic('info','sdk-already-ready');return Promise.resolve(window.google.maps);}
  if (typeof key !== 'string' || !key.trim()) {mapDiagnostic('error','sdk-key-missing',{code:'MAPS_KEY_MISSING',keyConfigured:false,message:'No browser key reached the client. Check the running Next.js environment and deployed build.'});return Promise.reject(failure('MAPS_KEY_MISSING', 'The browser Maps key is missing.'));}
  if (pending) return pending;
  const started=Date.now();
  mapDiagnostic('info','sdk-load-start',{keyConfigured:true,origin:window.location?.origin??''});
  const attempt = new Promise((resolve, reject) => {
    let script;
    let timer;
    let settled = false;
    const callback = '__edenAdminGoogleMapsLoaded';
    const finish = error => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      delete window[callback];
      if (error) {mapDiagnostic('error','sdk-load-failed',{code:error.code,elapsedMs:Date.now()-started,message:mapsErrorMessage(error)});script?.remove(); reject(error);}
      else {mapDiagnostic('info','sdk-ready',{elapsedMs:Date.now()-started,mapLibraryReady:!!window.google?.maps?.Map,markerLibraryReady:!!window.google?.maps?.marker?.AdvancedMarkerElement});resolve(window.google.maps);}
    };
    window[callback] = () => {
      // A failed SDK callback must reject, not leave a pending promise after
      // clearing its timer. Never read window.google.maps before validating it.
      finish(ready() ? undefined : failure('MAPS_SDK_UNAVAILABLE', 'Maps libraries unavailable.'));
    };
    try {
      script = document.createElement('script');
      script.id = 'eden-admin-google-maps-sdk';
      script.dataset.edenMaps = 'sdk';
      script.onload = () => mapDiagnostic('info','sdk-script-downloaded',{elapsedMs:Date.now()-started,mapLibraryReady:!!window.google?.maps?.Map,markerLibraryReady:!!window.google?.maps?.marker?.AdvancedMarkerElement});
      script.onerror = () => finish(failure('MAPS_NETWORK', 'Maps script could not load.'));
      const url = new URL('https://maps.googleapis.com/maps/api/js');
      for (const [name, value] of Object.entries({ key: key.trim(), libraries: 'marker', loading: 'async', callback, v: 'weekly' })) url.searchParams.set(name, value);
      script.src = url.toString(); script.async = true;
      timer = setTimeout(() => finish(failure('MAPS_TIMEOUT', 'Maps script timed out.')), 20000);
      document.head.append(script);
      mapDiagnostic('info','sdk-script-inserted',{keyConfigured:true});
    } catch { finish(failure('MAPS_NETWORK', 'Maps script injection failed.')); }
  });
  pending = attempt;
  // Synchronous injection failures and asynchronous failures are both retryable.
  void attempt.catch(() => { if (pending === attempt) pending = undefined; });
  return attempt;
}
