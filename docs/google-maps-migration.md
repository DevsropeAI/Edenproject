# Google Maps migration — web map displays

The shared `PropertyMap` uses Google Maps on **web**. It is reused for the
property picker, saved-property location view and customer's live contractor
location view. Its `LatLng` input and confirmed-coordinate return value have
not changed. The geolocator GPS flow, saved coordinates, booking API, location
uploads, authentication and privacy checks are unchanged.

The contractor marketplace map also uses Google Maps on web with the same
marker configuration, filters and details. The admin map and walking-route
layers now render through Google Maps, retaining existing polling, contractor
directory, filters, detail cards, and disconnected walking segments.

Native Android/iOS maps retain their existing renderer until separate native
SDK keys/configuration are available. A browser-restricted key cannot be reused
as an Android-restricted key. No native migration is claimed in this phase.

Address search/reverse lookup still uses the existing configured backend
provider. The optional Google search adapter has been implemented and tested
but NOT activated: Geocoding API and Places API (New) setup was postponed by
the user. No existing search credentials or provider flags were changed.

## Local setup

Enable Maps JavaScript API and billing in the Google Cloud project. Set
**Website application restrictions** and API restrictions on the browser key.
OAuth authorized origins/redirect URIs are a separate setting and do not restrict
this key. Allow both the app and admin domains, plus the exact local hosts used
for testing. A native Android SDK needs its own Android-restricted key later.

The setup script reads `EDEN_GOOGLE_MAPS_WEB_KEY` from the process environment
or backend `.env`, falling back to the existing `eden_map_api` entry. Only
use a **browser-restricted** key for these entries. It exports no OAuth client
ID, client secret, database setting or server geocoding key.

From the project root:

```powershell
node scripts/configure-google-maps.mjs
flutter run -d chrome --web-port 52207
```

Allow `http://localhost:52207/*` in the key's Website restrictions for that
command. Existing API origin/CORS restrictions must also allow that local app
origin. Alternatively, keep your existing Flutter port and allow that origin.
If Flutter is already running, stop it first: a hot reload does not reload
`web/index.html` or register the new plugin.

The setup script also adds/updates only `EDEN_GOOGLE_MAPS_WEB_KEY` in
`admin/.env.local`, preserving the other admin settings. Restart Next.js after
running the script. On the deployed admin server, set that environment value
to the website-restricted map key; do not put a server geocoding key there.

The generated `web/google_maps_config.js` is Git-ignored. A browser key is
necessarily visible in the delivered browser app, so domain/API restrictions
remain essential. Do not put a server-restricted key in it. Regenerate this
file on a new checkout or build machine before building.

```powershell
node scripts/configure-google-maps.mjs
flutter build web --release --dart-define=EDEN_API_URL=https://edenbackend.tripleimpacto.shop/api
```

The generated browser configuration and loader are copied into `build/web`.
Deploy the complete `build/web` folder as before. No database migration.

Admin maps use Google's Advanced Markers. For initial testing the adapter uses
Google's `DEMO_MAP_ID`. Set `EDEN_GOOGLE_MAPS_MAP_ID` in the admin environment to
your own JavaScript map ID for production. This is a map configuration ID, not
another secret API key. Enable Maps JavaScript API on the same project as the
browser key and authorize every actual app/admin origin.

## Review checklist

1. Customer: add/edit a property, open the location picker. Confirm Google map
   renders and current-location permission/GPS still places the pin.
2. Tap a different position, confirm **Use this pin**, and save. Reopen the
   property and confirm the same position. Existing reverse lookup and city
   preservation should behave as before.
3. View a saved property's map; it should show the saved pin without requesting
   location permission or offering editing controls.
4. For an en-route booking, share contractor location in a separate browser
   session. Customer's Google marker should follow the same existing updates.
5. With an unavailable SDK or missing browser configuration, the form should
   remain usable and show a retry/manual-entry message.
6. If Google displays a billing/key/domain error, check browser console and
   Google Cloud settings. Those settings cannot be inferred from a key's format.

Billing/key validity and real-device GPS need browser verification; successful
compilation alone does not verify them. No contractor dashboard redesign is
included in this phase.

7. Contractor job map: toggle all existing filters, tap pins, and open/close
   detail dialogs. Customer/large/active/completed pins must differ from blue
   contractor circles; offline circles remain outlined/faded.
8. Admin Map: customer/contractor filters, small/large/active/completed filters,
   record search, directory selection, details and refresh must still work.
9. Admin Door-to-door: choose a contractor/date/shift and verify route lines,
   start/end/current markers and gaps. Route segments must never connect over
   recorded gaps. Active shifts retain the existing 15-second polling.

## Deferred Google search activation

When the separate server key/APIs are ready, these backend environment settings
enable the new adapter (not enabled automatically by the map setup script):

```dotenv
GOOGLE_MAPS_SERVER_API_KEY=your_server_key
GEOCODING_PROVIDER=google
GEOCODING_AUTOCOMPLETE_PROVIDER=google
```

Enable Geocoding API and Places API (New), restrict the server key to those APIs
and the backend server's outbound IP where applicable. Never export that key
to Flutter or Next.js browser props. The browser map key and server lookup key
are deliberately separate. Keep current provider settings until ready.

Existing search/reverse endpoints retain their response fields; autocomplete
predictions include `placeId`/`needsDetails`. New `GET /api/geo/place` resolves
only the selected prediction and requires login. Registration has a separately
rate-limited `GET /api/auth/work-city-place`, forced to city-only results.
Predictions/details share a session token; no batch prefetch of place details.
Google lookup results bypass the old in-memory provider cache. No schema or
existing saved-city matching changes were made.

Before production Google search activation, review Google's address data
storage/attribution terms for the application's persistent city/property data.
No city/property retention changes or automatic cleanup were introduced here.
See https://developers.google.com/maps/documentation/places/web-service/policies
and https://developers.google.com/maps/documentation/geocoding/policies.

## Files changed or added

- `.gitignore`
- `pubspec.yaml`, `pubspec.lock`
- `lib/features/home/presentation/screens/property_map.dart`
- `lib/features/home/presentation/screens/marketplace_map.dart`
- `lib/features/home/presentation/screens/google_marketplace_canvas.dart`
- `lib/features/home/presentation/screens/address_search_field.dart` (search adapter, inactive until configured)
- `lib/core/maps/google_maps_loader.dart`
- `lib/core/maps/google_maps_loader_stub.dart`
- `lib/core/maps/google_maps_loader_web.dart`
- `web/index.html`, `web/google_maps_loader.js`
- `scripts/configure-google-maps.mjs`, `scripts/google-maps-loader.test.mjs`
- `admin/app/page.js`, `admin/app/dashboard.js`, `admin/app/marketplace-map.js`
- `admin/app/google-map-sdk.mjs`, `admin/app/google-map-adapter.mjs`, `admin/app/google-map-adapter.test.mjs`
- `backend/geocoding.mjs`, `backend/geocoding-provider.mjs`, `backend/google-geocoding.mjs`, `backend/google-geocoding.test.mjs`
- `backend/server.mjs`, `backend/geocoding-routes.test.mjs`, `test/address_search_field_test.dart` (inactive Google search adapter)
- `docs/google-maps-migration.md`

Local generated/configured files (ignored, not committed): `web/google_maps_config.js`, `admin/.env.local`.
No migrations. No database accessed or changed. New optional search endpoints
are listed above; map API contracts did not change.

Later dashboard addition: see `contractor-map-dashboard.md` for the synchronized
job-card map and the explicitly approved pre-acceptance exact-location rule.
