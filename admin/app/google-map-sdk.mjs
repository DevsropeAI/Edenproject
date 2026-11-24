let pending;
export function loadGoogleMaps(key) {
  if (window.google?.maps?.marker?.AdvancedMarkerElement) return Promise.resolve(window.google.maps);
  if (pending) return pending;
  if (!key) return Promise.reject(new Error('Configure the browser Google Maps key.'));
  pending = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    const callback = '__edenAdminGoogleMapsLoaded';
    const finish = error => {
      clearTimeout(timer); delete window[callback];
      if (error) { script.remove(); pending = undefined; reject(error); }
      else resolve(window.google.maps);
    };
    window[callback] = () => finish();
    script.onerror = () => finish(new Error('Google Maps could not load.'));
    const url = new URL('https://maps.googleapis.com/maps/api/js');
    for (const [name, value] of Object.entries({ key, libraries: 'marker', loading: 'async', callback, v: 'weekly' })) url.searchParams.set(name, value);
    script.src = url.toString(); script.async = true;
    const timer = setTimeout(() => finish(new Error('Google Maps loading timed out.')), 20000);
    document.head.append(script);
  });
  return pending;
}
