# Customer per-booking progress indicators

## Behavior

- A bell appears on the customer's tab when any booking in that tab has unread
  progress updates. Each affected booking card has its own bell.
- Merely switching tabs does not mark updates read. Opening that booking's
  details or messages acknowledges the loaded update version. Other jobs stay
  marked until viewed. Completed bookings share the same read state in Completed
  and Past, so reading one clears its indicators in both categories.
- Current, visible detail/chat pages acknowledge new loaded updates while open.
  Covered routes and backgrounded apps do not. A newer update that arrives
  during an acknowledgement remains unread until it has loaded into the view.
- Chat messages retain separate read counters: viewing details does not mark
  chat messages read. Existing notification snackbars/history remain.
- Opening Messages coalesces its progress acknowledgement with the visible-route
  reader and finishes it before updating chat read counters, avoiding competing
  read requests on the same booking version.
- The normal workflow now records arrival, work start, completion and reopening
  as well as acceptance, en route and submission. Contractor release/cancellation
  still reopens the customer booking, which appears in New with an update bell.
  Actual completed/cancelled records stay in history; status rules did not change.

## Persistence and API

Existing `POST /api/bookings/:id` accepts a new customer-only action:

```json
{ "action": "read-updates", "version": 7 }
```

The version is the highest notice version in the booking snapshot loaded by
the customer. The owner must match the authenticated customer; future, negative
or malformed versions are rejected. Acknowledgements use existing optimistic
booking concurrency and retry on a later refresh if a competing change wins.
They never advance a job, clear a newer notice, or change chat read counters.

Read state is stored as `customerNoticeReadVersion` in existing booking details
JSON, defaulting to zero for older rows. No table/column/migration was added.
The response omits this customer-only metadata for contractors. Existing notice
history remains; previously stored notices without read metadata may show a bell
until first viewed.

No database writes, migrations or deployed operations were run by the agent.
Backend acknowledgement tests use mocks; actual reads persist when users view
their bookings with the updated backend running.

## Manual test

Restart the existing local backend and fully restart Flutter after adding the
new Dart file. Deploy the backend together with the frontend later; older
backends do not support the new read acknowledgement action.

1. Have two customer bookings accepted by contractors. After normal polling,
   check In progress's bell and both job-card bells.
2. Switch to In progress: neither card should clear just from switching tabs.
3. View the first job's details and return. Only that job clears; the tab and
   second job stay marked. Open the second job's Messages and return: its
   progress badge and the tab badge clear.
4. Advance through On the way, Arrived, Working, Submitted. Check that later
   updates reappear. Keep details open to see new loaded updates acknowledged.
5. Release/cancel the contractor assignment: the booking returns to New with a
   bell. Verify completed records' badges in Completed/Past share read state.
6. Refresh/sign in again: acknowledged versions stay read, while unrelated job
   updates remain unread. Verify unread chat dots and normal job actions.

## Files changed or added

- `backend/marketplace.mjs`
- `backend/booking-update-read.test.mjs` (new)
- `lib/features/home/marketplace.dart`
- `lib/features/home/presentation/screens/customer_booking_tabs.dart`
- `lib/features/home/presentation/screens/customer_booking_update_reader.dart` (new)
- `lib/features/home/presentation/screens/marketplace_screens.dart`
- `lib/features/home/presentation/screens/demo_settings_screen.dart`
- `test/customer_booking_updates_test.dart` (new)
- `docs/customer-booking-update-badges.md` (new)

Tests cover ownership, acknowledgement validation/concurrency, milestone notice
creation, per-job/tab clearing, overlapping history tabs, newer updates during
an in-flight read, hidden routes, and unchanged customer tabs/chat indicators.
Real multi-session Chrome/GPS/registration workflows still need manual review.
