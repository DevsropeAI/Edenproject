# Contractor offer information and registration services

## Completed

- Eligible available jobs expose their saved exact address/pin, job instructions,
  property instructions, property type/size and measurements (driveway, yards,
  walkway) before acceptance, as requested. Photos/reference photos and unrelated
  structured address metadata remain hidden. Pending large jobs and jobs
  assigned to other contractors remain excluded.
- Contractor job details display the saved location map inline when a pin exists.
  Dashboard selection previews and job details share the same requirements widget.
  Yard selections display **Yes** even if no optional size was entered.
- Registration loads all active catalog services, preserves a primary service
  in `users.service`, and allows multiple additional services in the existing
  `contractor_services` table. Account, city (when selected) and additional
  services are committed together or rolled back. Existing profile editing,
  service/city matching and single-primary registrations remain available.
- The public account-options response identifies whether the backend has loaded
  offer-details and registration-services support. An old backend produces an
  explicit update/restart notice instead of silently suggesting that saved pins
  do not exist. The registration notice includes a refresh action.

## Local diagnosis and restart

The local API process on port 3001 was started at 12:35 on 24 November 2026,
before these changes. It must be restarted to serve the new offer fields and
save multiple registration services. Merely restarting Flutter does not reload
the Node API.

Stop the existing backend with **Ctrl+C** in its terminal, then run:

```powershell
npm --prefix backend start
```

Keep the existing database/configuration settings. No migration is needed.
Stop the old Flutter process with **q** or **Ctrl+C**, then restart it on your
already authorized, free local port. For the established 52207 setup:

```powershell
node scripts/configure-google-maps.mjs
flutter run -d chrome --web-port 52207
```

If the backend was restarted while the frontend remained open, use
**Refresh jobs** or **Refresh service options** to reload its capabilities.
On deployment the backend code and frontend must be updated together; a new
frontend cannot recover coordinates/instructions redacted by an old backend.

## API changes

- Existing `GET /api/auth/options`: additive `contractorOfferDetails` and
  `contractorRegistrationServices` boolean capabilities.
- Existing `POST /api/auth/register`: optional `serviceIds` array for additional
  active service IDs. Existing `service`, city, phone/SMS and registration
  response contracts remain. Invalid, duplicate, inactive or customer-role
  selections are rejected. Empty/omitted extras retain the old flow.
- Existing contractor `GET /api/bookings`: the approved offer instructions and
  `property.measurements` are now returned, in addition to the already approved
  address/pin. Eligibility and admin assignment still control access.

No new endpoints, migration, seed or database changes were run. No deployed
database or MySQL users/passwords/privileges were accessed or changed.

## Manual test

1. Restart the backend, refresh the contractor dashboard, and select an eligible
   available job with a saved property pin. Verify the pin and exact address.
2. Open the job page: verify inline map, driveway size, front/back yard choices
   and sizes, walkway, property instructions and job instructions. Check the
   same data in the dashboard description preview.
3. Old jobs without saved pins remain readable, without invented coordinates.
   Choose/save their location from the customer property editor if needed.
4. Register a contractor with a new primary service and two additional services.
   Sign in normally and check the additional selections in Profile. Check job
   matching for those services in the saved city after normal verification.
5. Invalid/inactive services must not create a partial account. Test ordinary
   customer registration and original single-primary contractor registration.
6. Pending large jobs stay in admin; only the assigned contractor receives them.
   Verify accept/decline/release/cancel, chat and live-location behavior normally.

## Deferred

Google Geocoding can translate a selected GPS/map pin into street, city,
state/province, postal code and country. Its adapter remains inactive until
the separately requested Geocoding/Places server key and APIs are available.
The existing lookup provider and its attribution remain accurate meanwhile.
No key was added or changed for this task. Real Chrome maps/GPS and complete
account creation still need the user's manual check; automated registration
tests use transactional mocks, not real database writes.

## Files for this update

- `backend/server.mjs`, `backend/marketplace.mjs`
- `backend/addresses.test.mjs`, `backend/marketplace.test.mjs`
- `backend/registration-services.test.mjs` (new)
- `lib/features/auth/providers/account_options_provider.dart` (new)
- `lib/features/auth/presentation/screens/registration_services_picker.dart` (new)
- `lib/features/auth/presentation/screens/account_form_screen.dart`
- `lib/features/home/presentation/screens/marketplace_screens.dart`
- `lib/features/home/presentation/screens/contractor_jobs_browser.dart`
- `test/registration_services_picker_test.dart` (new)
- `docs/contractor-map-dashboard.md`, this report
