// Small rendering adapter for the existing map/walking layer lifecycle.
// Data, filters, privacy, polling and walking-gap segmentation stay in their current components.
export function googleMapAdapter(g, element, mapId = 'DEMO_MAP_ID') {
  const point = ([lat, lng]) => ({ lat, lng });
  const groups = new Set();
  const listeners = [];
  const native = new g.Map(element, { center: { lat: 20, lng: 0 }, zoom: 2, maxZoom: 19, mapId, streetViewControl: false, mapTypeControl: false });
  const map = {
    native,
    setView(position, zoom) { native.setCenter(point(position)); native.setZoom(zoom); return map; },
    fitBounds(positions, options = {}) {
      const bounds = new g.LatLngBounds(); positions.forEach(position => bounds.extend(point(position)));
      native.fitBounds(bounds, options.padding?.[0] ?? 45);
      if (options.maxZoom) listeners.push(g.event.addListenerOnce(native, 'idle', () => {
        if (native.getZoom() > options.maxZoom) native.setZoom(options.maxZoom);
      }));
    },
    on(event, callback) { listeners.push(native.addListener(event, callback)); return map; },
    invalidateSize() { const center = native.getCenter(); g.event.trigger(native, 'resize'); if (center) native.setCenter(center); },
    hasLayer(layer) { return groups.has(layer); },
    removeLayer(layer) { layer.clearLayers(); groups.delete(layer); },
    remove() { for (const layer of groups) layer.clearLayers(); groups.clear(); listeners.forEach(listener => listener.remove()); g.event.clearInstanceListeners(native); element.replaceChildren(); },
  };
  const api = {
    layerGroup() {
      const items = new Set();
      const group = {
        map: null,
        addTo(owner) { group.map = owner; groups.add(group); return group; },
        add(item) { items.add(item); item.map = group.map.native; },
        clearLayers() { for (const item of items) { g.event.clearInstanceListeners(item); if (item.setMap) item.setMap(null); else item.map = null; } items.clear(); },
      };
      return group;
    },
    divIcon(options) { return options; },
    marker(position, { title, icon }) {
      const marker = new g.marker.AdvancedMarkerElement({ position: point(position), title, content: icon.html,
        ...(icon.html.className?.includes('map-marker--circle') ? { anchorTop: '-50%' } : {}),
      });
      return { addTo(layer) { layer.add(marker); return this; }, on(event, callback) { marker.addListener(event, callback); return this; } };
    },
    polyline(positions, options) {
      const line = new g.Polyline({
        path: positions.map(point), strokeColor: options.color, strokeWeight: options.weight,
        strokeOpacity: options.dashArray ? 0 : 1,
        ...(options.dashArray ? { icons: [{ icon: { path: 'M 0,-1 0,1', strokeOpacity: 1, strokeWeight: options.weight, scale: 3 }, offset: '0', repeat: '14px' }] } : {}),
      });
      return { addTo(layer) { line.setMap(layer.map.native); layer.add({ setMap: value => line.setMap(value) }); return this; } };
    },
    circleMarker(position, options) {
      const circle = document.createElement('span');
      Object.assign(circle.style, {
        display: 'block', width: `${options.radius * 2}px`, height: `${options.radius * 2}px`, borderRadius: '50%',
        border: `${options.weight ?? 2}px ${options.dashArray ? 'dashed' : 'solid'} ${options.color}`,
        background: options.fillOpacity === 0 ? 'transparent' : options.fillColor ?? options.color,
      });
      const marker = new g.marker.AdvancedMarkerElement({ position: point(position), content: circle, anchorTop: '-50%' });
      return { addTo(layer) { layer.add(marker); return this; }, bindTooltip(text) { marker.title = text; return this; } };
    },
  };
  return { map, api };
}
