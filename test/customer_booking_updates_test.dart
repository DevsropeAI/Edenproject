import 'dart:async';

import 'package:dio/dio.dart';
import 'package:eden_frontend/core/network/api_client.dart';
import 'package:eden_frontend/core/storage/secure_storage.dart';
import 'package:eden_frontend/features/auth/providers/auth_provider.dart';
import 'package:eden_frontend/features/auth/domain/auth_state.dart';

import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:eden_frontend/features/home/presentation/screens/customer_booking_tabs.dart';
import 'package:eden_frontend/features/home/presentation/screens/customer_booking_update_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Booking updated(
  int id, {
  int version = 1,
  int read = 0,
  JobStatus status = JobStatus.accepted,
}) => Booking(
  id: id,
  property: const Property(1, 'Home', 'Main Street', 'Large', ''),
  service: Service.paver,
  date: DateTime(2026, 11, 25),
  total: 45,
  notes: '',
  status: status,
  customerNotices: [
    (status: status, version: version, at: DateTime(2026, 11, 24)),
  ],
  customerNoticeReadVersion: read,
);

class ReadBookings extends Bookings {
  ReadBookings(this.initial);
  final List<Booking> initial;
  final reads = <(int, int)>[];
  Completer<void>? gate;
  @override
  List<Booking> build() => initial;
  void replace(List<Booking> bookings) => state = bookings;
  @override
  Future<void> markUpdatesRead(int id, int version) async {
    reads.add((id, version));
    final waiting = gate;
    gate = null;
    if (waiting != null) await waiting.future;
    state = [
      for (final booking in state)
        if (booking.id == id)
          booking.update(customerNoticeReadVersion: version)
        else
          booking,
    ];
  }
}

class IdleAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState.unauthenticated();
}

class AcknowledgementApi extends ApiClient {
  AcknowledgementApi() : super(SecureStorage());
  final gate = Completer<void>();
  int calls = 0;
  @override
  Future<Response> post(String path, {dynamic data}) async {
    calls++;
    await gate.future;
    return Response(
      requestOptions: RequestOptions(path: path),
      data: {'customerNoticeReadVersion': data['version']},
    );
  }
}

class RealReadBookings extends Bookings {
  @override
  List<Booking> build() => [updated(1)];
  @override
  Future<void> refresh({bool silent = false}) async {}
}

void main() {
  test('chat and visible-route progress acknowledgements share one in-flight request', () async {
    final api = AcknowledgementApi();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(IdleAuth.new),
        apiClientProvider.overrideWithValue(api),
        bookingsProvider.overrideWith(RealReadBookings.new),
      ],
    );
    addTearDown(container.dispose);
    final records = container.read(bookingsProvider.notifier);
    final first = records.markUpdatesRead(1, 1);
    final second = records.markUpdatesRead(1, 1);
    expect(identical(first, second), true);
    expect(api.calls, 1);
    api.gate.complete();
    await Future.wait([first, second]);
    expect(container.read(bookingsProvider).single.hasUnreadUpdates, false);
  });

  testWidgets(
    'reopened jobs mark New, and reading a completed job clears both Completed and Past indicators',
    (tester) async {
      var jobs = [
        updated(1, status: JobStatus.searching),
        updated(2, status: JobStatus.completed),
      ];
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
      await tester.pumpAndSettle();
      for (final tab in ['newBookings', 'completed', 'past']) {
        expect(
          find.byKey(ValueKey('customer-tab-update-$tab')),
          findsOneWidget,
        );
      }
      update(
        () =>
            jobs = [jobs.first, jobs.last.update(customerNoticeReadVersion: 1)],
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('customer-tab-update-newBookings')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('customer-tab-update-completed')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('customer-tab-update-past')),
        findsNothing,
      );
    },
  );

  test(
    'legacy defaults and read metadata preserve separate chat read state',
    () {
      expect(updated(1).hasUnreadUpdates, true);
      final read = updated(1).update(customerNoticeReadVersion: 1);
      expect(read.hasUnreadUpdates, false);
      expect(read.customerRead, 0);
      expect(
        read.update(status: JobStatus.working).customerNoticeReadVersion,
        1,
      );
    },
  );

  testWidgets(
    'opening one job clears only that card; the tab stays marked until every job is viewed',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(380, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final records = ReadBookings([updated(1), updated(2)]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bookingsProvider.overrideWith(() => records)],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) => Scaffold(
                body: SingleChildScrollView(
                  child: CustomerBookingTabs(
                    bookings: ref.watch(bookingsProvider),
                    onRefresh: () async {},
                    onOpen: (job) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => Consumer(
                          builder: (context, ref, child) =>
                              CustomerBookingUpdateReader(
                                booking: ref
                                    .watch(bookingsProvider)
                                    .firstWhere(
                                      (booking) => booking.id == job.id,
                                    ),
                                child: Scaffold(
                                  appBar: AppBar(title: const Text('Details')),
                                  body: const Text('Job information'),
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('customer-tab-update-inProgress')),
        findsOneWidget,
      );
      for (final id in [1, 2]) {
        final details = find.descendant(
          of: find.byKey(ValueKey('customer-booking-$id')),
          matching: find.text('View details'),
        );
        await tester.ensureVisible(details);
        await tester.tap(details);
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('customer-booking-update-$id')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('customer-tab-update-inProgress')),
          id == 1 ? findsOneWidget : findsNothing,
        );
      }
      expect(records.reads, [(1, 1), (2, 1)]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a newer visible update is acknowledged after an older in-flight acknowledgement',
    (tester) async {
      final records = ReadBookings([updated(1)]);
      final gate = Completer<void>();
      records.gate = gate;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bookingsProvider.overrideWith(() => records)],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) => CustomerBookingUpdateReader(
                booking: ref.watch(bookingsProvider).single,
                child: const Scaffold(body: Text('Details')),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      records.replace([updated(1, version: 2)]);
      await tester.pump();
      expect(records.reads, [(1, 1)]);
      gate.complete();
      await tester.pumpAndSettle();
      expect(records.reads, [(1, 1), (1, 2)]);
    },
  );

  testWidgets(
    'a covered details route does not acknowledge updates until visible again',
    (tester) async {
      final records = ReadBookings([updated(1, read: 1)]);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [bookingsProvider.overrideWith(() => records)],
          child: MaterialApp(
            navigatorKey: nav,
            home: Consumer(
              builder: (context, ref, child) => CustomerBookingUpdateReader(
                booking: ref.watch(bookingsProvider).single,
                child: const Scaffold(body: Text('Details')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Another screen')),
        ),
      );
      await tester.pumpAndSettle();
      records.replace([updated(1, version: 2)]);
      await tester.pumpAndSettle();
      expect(records.reads, isEmpty);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(records.reads, [(1, 2)]);
    },
  );
}
