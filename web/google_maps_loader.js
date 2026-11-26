// Loaded on demand by the property map, leaving the rest of Eden usable on failure.
(() => {
  let pending;
  const log=(level,event,details={})=>console[level](`[Eden Maps][web][diagnostics-v1] ${event}`,details);
  log('info','loader-ready');
  const previousAuthFailure=window.gm_authFailure;
  window.gm_authFailure=()=>{
    log('error','google-auth-failure',{code:'MAPS_AUTH',message:'Check the Google Console error, API restrictions, Maps JavaScript API activation and billing.'});
    if(typeof previousAuthFailure==='function')previousAuthFailure();
  };
  window.edenLoadGoogleMaps = () => {
    if (window.google?.maps?.Map) return Promise.resolve();
    if (pending) return pending;
    const key = window.EDEN_GOOGLE_MAPS_API_KEY;
    if (!key) {log('error','key-missing',{keyConfigured:false});return Promise.reject(new Error('Google Maps is not configured.'));}
    const started=Date.now();
    log('info','sdk-load-start',{keyConfigured:true,origin:window.location?.origin??''});
    pending = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      const callback = '__edenGoogleMapsLoaded';
      let timer;
      const finish = error => {
        clearTimeout(timer);
        delete window[callback];
        if (error) {
          log('error','sdk-load-failed',{message:error.message,elapsedMs:Date.now()-started});
          script.remove();
          pending = undefined;
          reject(error);
        } else {log('info','sdk-ready',{elapsedMs:Date.now()-started,mapLibraryReady:!!window.google?.maps?.Map});resolve();}
      };
      window[callback] = () => finish();
      script.onerror = () => finish(new Error('Google Maps could not load.'));
      const url = new URL('https://maps.googleapis.com/maps/api/js');
      url.searchParams.set('key', key);
      url.searchParams.set('callback', callback);
      url.searchParams.set('loading', 'async');
      url.searchParams.set('libraries', 'marker');
      url.searchParams.set('v', 'weekly');
      script.src = url.toString();
      script.async = true;
      timer = setTimeout(() => finish(new Error('Google Maps loading timed out.')), 20000);
      document.head.append(script);
      log('info','sdk-script-inserted');
    });
    return pending;
  };
})();
