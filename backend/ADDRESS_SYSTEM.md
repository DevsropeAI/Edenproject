# Structured property addresses and work cities

The code is prepared. The database migration has not been approved or applied.
Existing API clients and legacy address JSON remain supported.

## Database review and activation

Review migrations/001_structured_addresses.review.sql. The runner checks existing
columns and constraint names, uses a database lock, and records version
001_structured_addresses only after success. MySQL DDL is additive and commits
implicitly. A failure may leave some additive objects in place; rerunning finishes
the remaining steps.

After approval, set EDEN_APPLY_ADDRESS_MIGRATION=true for the backend startup.
Remove that flag after successful application. The backend checks the recorded
version at startup. Until applied, structured property saves and work-city saves
return a clear unavailable response; legacy API saves continue working.

No cities are seeded. Each valid structured property save or selected work city
creates/reuses its city identity (name, state, country). Existing users.area values
are never overwritten.

After real city records exist, generate an exact-match report:
node backend/scripts/report-contractor-cities.mjs

Apply unambiguous exact-name matches only when reviewed:
node backend/scripts/report-contractor-cities.mjs --apply

The report lists unmatched/ambiguous contractor IDs and service-area text. Protect
the report as account data. No backfill or report was executed during this change.

## Backend configuration

Explicit search and reverse with public Nominatim:
GEOCODING_PROVIDER=nominatim
GEOCODING_CONTACT_EMAIL=<your monitored contact email>

Optional hosted autocomplete:
GEOCODING_AUTOCOMPLETE_PROVIDER=geoapify
GEOAPIFY_API_KEY=<server-side key>

Search and reverse can also use Geoapify:
GEOCODING_PROVIDER=geoapify

Unset providers return capabilities=false and manual entry remains available.
Restart the API after changing environment values. Flutter reads capabilities,
so enabling autocomplete requires no Flutter source change. Search uses a button
or keyboard submit, never typing. Autocomplete uses a 400ms debounce with Geoapify.

Nominatim is backend-only, limited to at most one start per 1.1 seconds,
with a bounded queue, five-minute cache and coalesced identical requests.
Run a single backend worker for public Nominatim. Multi-worker/multi-server use
requires a shared global throttle or a hosted provider before scaling.
https://operations.osmfoundation.org/policies/nominatim/

Contractor registration supports city selection through separate rate-limited public
lookup endpoints. General /geo endpoints still require login. After login, work city
can be changed under Profile > Edit profile. Existing area text is retained.

## Endpoints (all require a customer or contractor login)

GET /api/geo/capabilities
GET /api/geo/search?q=...&country=PK
GET /api/geo/autocomplete?q=...&country=PK
GET /api/geo/reverse?lat=...&lng=...
GET /api/contractor/work-location (contractor only)
POST /api/contractor/work-location (contractor only), body {city: suggestion}

The existing /api/properties POST additionally accepts structuredAddress,
measurements and addressSelection. Existing fields/signatures remain supported.
cityId is additional response data. Unaccepted offers retain the old whitelist
and do not expose the new structured address, measurements or city identity.
City IDs match only when both are available, otherwise the existing city-text
and service fallback applies.

The picker and map implementation are unchanged. Reverse lookup happens once
after the existing picker returns confirmed coordinates. It does not run on each
pointer movement or during the live tracking loop.

## Manual checks after migration approval and deployment

1. Search Lahore and Toronto explicitly. Confirm requests occur only on submit.
2. Enable Geoapify autocomplete, restart API, reopen form and verify debounce.
3. Select a result and edit fields. Confirm no pin movement from manual typing.
4. Confirm a map/current-location pin and check reverse-filled address fields.
5. Use Update pin from address and explicitly choose a returned location.
6. Save measurements, reopen the property, and inspect the accepted job details.
7. Save a contractor work city. Verify city-ID matching and legacy fallback.
8. Inspect an unaccepted offer response for absence of street, postal code,
   structured address, coordinates and driveway/yard/walkway details.
9. Disable providers and verify manual save and friendly lookup errors.
10. Verify old records, booking/chat/photos/review/tracking and admin workflows.

