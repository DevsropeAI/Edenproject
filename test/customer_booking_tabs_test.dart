import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:eden_frontend/features/home/presentation/screens/customer_booking_tabs.dart';
import 'package:eden_frontend/features/home/presentation/screens/google_marketplace_canvas.dart';
import 'package:eden_frontend/features/home/presentation/screens/property_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Booking booking(int id, JobStatus status) => Booking(
  id: id,
  property: Property(id, 'Home', '$id Main Street', 'Large', ''),
  service: Service.snow,
  date: DateTime(2026, 11, 25),
  scheduledDate: '2026-11-25',
  total: 45,
  notes: '',
  status: status,
);

void main() {
  final bookings = [
    for (final status in JobStatus.values) booking(status.index + 1, status),
  ];
  test('customer tabs distinguish unaccepted, in-progress, completed and past bookings', () {
    expect(
      customerTabBookings(
        bookings,
        CustomerBookingTab.newBookings,
      ).map((booking) => booking.status),
      [JobStatus.searching],
    );
    expect(
      customerTabBookings(
        bookings,
        CustomerBookingTab.inProgress,
      ).map((booking) => booking.status),
      [
        JobStatus.accepted,
        JobStatus.enRoute,
        JobStatus.arrived,
        JobStatus.working,
        JobStatus.submitted,
      ],
    );
    expect(
      customerTabBookings(
        bookings,
        CustomerBookingTab.completed,
      ).map((booking) => booking.status),
      [JobStatus.completed],
    );
    expect(
      customerTabBookings(
        bookings,
        CustomerBookingTab.past,
      ).map((booking) => booking.status),
      [JobStatus.completed, JobStatus.cancelled],
    );
  });

  for (final width in [360.0, 480.0]) {
    testWidgets(
      'customer booking tabs and detail navigation work at $width without maps',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        int? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CustomerBookingTabs(
                    bookings: bookings,
                    onOpen: (booking) => opened = booking.id,
                    onRefresh: () async {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('customer-booking-1')),
          findsOneWidget,
        );
        await tester.tap(find.text('View details'));
        expect(opened, 1);
        for (final (tab, id) in [
          (CustomerBookingTab.inProgress, 2),
          (CustomerBookingTab.completed, 7),
          (CustomerBookingTab.past, 8),
        ]) {
          final chip = find.byKey(ValueKey('customer-tab-${tab.name}'));
          await tester.ensureVisible(chip);
          await tester.tap(chip);
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey('customer-booking-$id')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('customer-booking-1')),
            findsNothing,
          );
        }
        expect(find.byType(PropertyMap), findsNothing);
        expect(find.byType(GoogleMarketplaceCanvas), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'newly loaded in-progress orders appear first until the customer chooses a tab',
    (tester) async {
      var jobs = <Booking>[];
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setter) {
                  update = setter;
                  return CustomerBookingTabs(
                    bookings: jobs,
                    onOpen: (_) {},
                    onRefresh: () async {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      update(() => jobs = [booking(1, JobStatus.enRoute)]);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('customer-tab-inProgress')),
            )
            .selected,
        true,
      );
      await tester.tap(find.byKey(const ValueKey('customer-tab-newBookings')));
      update(() => jobs = [booking(1, JobStatus.submitted)]);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('customer-tab-newBookings')),
            )
            .selected,
        true,
      );
      expect(
        find.text('No bookings waiting for a contractor.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('refresh failure leaves tabs and retry usable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerBookingTabs(
            bookings: const [],
            onOpen: (_) {},
            onRefresh: () async => throw StateError('offline'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Refresh bookings'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not refresh bookings. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
