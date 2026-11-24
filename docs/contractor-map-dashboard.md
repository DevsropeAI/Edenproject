# Contractor map dashboard

## Behavior

The contractor **web** Jobs page now has Available, Active, Completed and
Cancelled tabs. The current tab's jobs are shown on Google Maps and in a
horizontal card list. Selecting a card highlights its pin, expands the map
and zooms toward it. Selecting a pin selects and scrolls to its card.
**Show all** clears the selection and fits the tab's visible pins again.

The selected job's preview opens the existing `/job-details/:id` page. The
existing acceptance, decline, release, cancellation, chat and progress actions
remain on that page. Availability, refresh, profile/earnings shortcuts and the
door-to-door entry remain available. Existing booking polling is reused.

No fake coordinates are assigned to jobs lacking pins: their cards remain
usable and the map explains that their saved location is missing.

## Approved location visibility change

The user explicitly approved exact property locations **before acceptance**.
The existing contractor bookings endpoint now returns the full combined
address and saved pin for eligible offers, including large jobs assigned to
that contractor by admin. It still excludes pending/unassigned large jobs,
offers assigned to someone else, and unmatched jobs.

Follow-up approval: job/property instructions and structured measurements are
now also visible before acceptance, so contractors can evaluate the work.
Photos, reference photos and unrelated structured address metadata remain
hidden. Existing city,
service, availability, decline and release matching rules are retained.

No migration, database modification, deployed connection or deployment was
performed. There are no new endpoints for this dashboard. Existing
`GET /api/bookings` has the approved address/pin visibility change. The admin
map endpoint remains unchanged.

## Run and manually test

Stop the old Flutter process with **q** or **Ctrl+C**, then start it again.
Hot reload is insufficient after adding new Dart libraries/assets and can
leave the browser displaying `Library not defined`.

```powershell
node scripts/configure-google-maps.mjs
flutter run -d chrome --web-port 52207
```

Restart the local backend in its own terminal so the new location visibility
rule is loaded. Existing backend configuration and migration flags must remain
unchanged. No migration is needed for this feature.

1. Create two matching small jobs with saved pins from a customer account.
2. Contractor: Available should show both cards and their exact-location pins.
3. Tap the second card: selected styling, larger map, zoomed pin and preview.
4. Tap the first pin: its card scrolls into view and becomes selected.
5. Tap **Show all**: both pins should be visible again.
6. Open the preview/**View job details**: verify the existing acceptance page.
7. Accept a job: it moves from Available into Active after refresh/polling.
8. Check Completed and Cancelled independently. Switching tabs clears selection.
9. Pending large requests must remain absent. Admin-assigned requests should
   appear for the assigned contractor only, including when that contractor is
   offline, as before.
10. Verify before-acceptance photos remain hidden while job instructions and
    yard/driveway/walkway details are visible; check chat indicators and
    acceptance/release/cancellation normally.
11. Old jobs without pins must still open from their cards.

## Checks and limits

Widget tests cover tab partitioning, admin-pending exclusions, offline assigned
offers, card/pin selection, map enlargement, overview reset, existing detail
navigation and missing pins at 360px/480px. Backend tests cover exact-location
whitelisting, continued instruction/photo privacy, assigned-only large offers,
city matching, job management and GPS authorization. The later instructions
and registration update is documented in `contractor-offer-details-and-registration.md`.

Real Google Maps rendering/key restrictions/GPS still require Chrome review.
Native Android/iOS retains the old dashboard until native map keys/configuration
are supplied. Google address/city search remains inactive as requested while
its separate APIs are unavailable. The existing admin Google map is unchanged
by this dashboard feature.

## Files changed for this dashboard

- `lib/features/home/presentation/screens/contractor_jobs_browser.dart` (new)
- `lib/features/home/presentation/screens/google_marketplace_canvas.dart`
- `lib/features/home/presentation/screens/marketplace_screens.dart`
- `lib/features/home/marketplace.dart` (read/preserve existing service category snapshot)
- `pubspec.yaml` (reuse shared marker configuration as a bundled asset)
- `backend/marketplace.mjs`
- `backend/marketplace.test.mjs`, `backend/addresses.test.mjs`
- `test/contractor_jobs_browser_test.dart` (new)
- `docs/contractor-map-dashboard.md` (new)
