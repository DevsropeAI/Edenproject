import assert from 'node:assert/strict';
import { test } from 'node:test';
import { googleMapAdapter } from './google-map-adapter.mjs';

function setup() {
  const created = { markers: [], lines: [], maps: [] };
  const g = {
    Map: class {
      constructor(element, options) { Object.assign(this, options); created.maps.push(this); }
      setCenter(value) { this.center = value; } getCenter() { return this.center; }
      setZoom(value) { this.zoom = value; } getZoom() { return this.zoom; }
      fitBounds(bounds) { this.bounds = bounds; }
      addListener() { return { remove() {} }; }
    },
    LatLngBounds: class { positions = []; extend(position) { this.positions.push(position); } },
    marker: { AdvancedMarkerElement: class {
      constructor(options) { Object.assign(this, options); created.markers.push(this); }
      addListener(event, callback) { this[event] = callback; }
    } },
    Polyline: class {
      constructor(options) { Object.assign(this, options); created.lines.push(this); }
      setMap(map) { this.map = map; }
    },
    event: { addListenerOnce(map, event, callback) { callback(); return { remove() {} }; }, trigger() {}, clearInstanceListeners() {} },
  };
  const element = { replaceChildren() { this.cleared = true; } };
  return { ...googleMapAdapter(g, element), created, element };
}

test('Google adapter retains custom marker content, selection and filter layer removal', () => {
  const { api, map, created } = setup();
  const layer = api.layerGroup().addTo(map);
  const content = { className: 'blue-contractor-circle' };
  let selected = false;
  api.marker([31.5, 74.3], { title: 'Contractor', icon: api.divIcon({ html: content }) })
    .addTo(layer).on('click', () => { selected = true; });
  assert.equal(created.markers[0].content, content);
  assert.deepEqual(created.markers[0].position, { lat: 31.5, lng: 74.3 });
  created.markers[0].click(); assert.equal(selected, true);
  layer.clearLayers(); assert.equal(created.markers[0].map, null);
});

test('walking segments remain separate lines and stop/start markers retain their style', () => {
  const previous = globalThis.document;
  globalThis.document = { createElement: () => ({ style: {} }) };
  try {
    const { api, map, created } = setup();
    const layer = api.layerGroup().addTo(map);
    for (const segment of [[[31, 74], [31.001, 74]], [[32, 75], [32.001, 75]]]) {
      api.polyline(segment, { color: '#A78BFA', weight: 4, dashArray: '8 6' }).addTo(layer);
    }
    api.circleMarker([31, 74], { color: '#A78BFA', fillColor: '#A78BFA', radius: 6, fillOpacity: 1 }).addTo(layer).bindTooltip('Start');
    assert.equal(created.lines.length, 2);
    assert.deepEqual(created.lines[0].path.at(-1), { lat: 31.001, lng: 74 });
    assert.deepEqual(created.lines[1].path[0], { lat: 32, lng: 75 });
    assert.equal(created.markers[0].title, 'Start');
    map.removeLayer(layer);
    assert.equal(map.hasLayer(layer), false);
    assert.ok(created.lines.every(line => line.map === null));
    assert.equal(created.markers[0].map, null);
  } finally { globalThis.document = previous; }
});

test('fit, focus and disposal retain map lifecycle behavior', () => {
  const { api, map, created, element } = setup();
  map.setView([31, 74], 13);
  assert.equal(created.maps[0].zoom, 13);
  map.fitBounds([[31, 74], [32, 75]], { maxZoom: 12 });
  assert.equal(created.maps[0].bounds.positions.length, 2);
  assert.equal(created.maps[0].zoom, 12);
  api.layerGroup().addTo(map);
  map.remove(); assert.equal(element.cleared, true);
});
