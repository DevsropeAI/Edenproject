# Customer booking tabs

Added the same shared booking tabs to Customer Home and Orders, without maps:

| Tab | Existing statuses shown |
| --- | --- |
| New | Searching/waiting for contractor acceptance, including admin-pending large requests |
| In progress | Accepted, on the way, arrived, working, awaiting customer approval |
| Completed | Completed only |
| Past | Completed and cancelled history |

Completed bookings intentionally also appear in Past because that tab is the
combined history requested by the user. The initial view chooses New if any
exist, otherwise In progress, then Completed/Past. Once the user chooses a tab,
polling preserves that choice while its contents/counts update.

Existing service catalog, booking creation, properties, prices, tracking,
notifications, backend state transitions and routes are unchanged. Cards open
the existing `/bookings/:id` page. No backend changes, endpoints, migrations or
database operations were needed for this update.

## Manual review

Fully restart Flutter after adding the new Dart file. Check Customer Home and
Orders with unaccepted, accepted/en-route, awaiting-approval, completed and
cancelled bookings. Verify counts, status labels, tab filtering, detail links,
refresh and unread-message buttons. Check that service browsing and Manage
properties remain available on Home. Neither tab section should show a map.
Existing maps inside order details are preserved.

## Files

- `lib/features/home/presentation/screens/customer_booking_tabs.dart` (new)
- `lib/features/home/presentation/screens/customer_home_screen.dart`
- `lib/features/home/presentation/screens/marketplace_screens.dart`
- `test/customer_booking_tabs_test.dart` (new)
- `docs/customer-booking-tabs.md` (new)
