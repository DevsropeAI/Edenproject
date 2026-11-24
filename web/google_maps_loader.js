// Loaded on demand by the property map, leaving the rest of Eden usable on failure.
(() => {
  let pending;
  window.edenLoadGoogleMaps = () => {
    if (window.google?.maps?.Map) return Promise.resolve();
    if (pending) return pending;
    const key = window.EDEN_GOOGLE_MAPS_API_KEY;
    if (!key) return Promise.reject(new Error('Google Maps is not configured.'));
    pending = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      const callback = '__edenGoogleMapsLoaded';
      let timer;
      const finish = error => {
        clearTimeout(timer);
        delete window[callback];
        if (error) {
          script.remove();
          pending = undefined;
          reject(error);
        } else resolve();
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
    });
    return pending;
  };
})();
