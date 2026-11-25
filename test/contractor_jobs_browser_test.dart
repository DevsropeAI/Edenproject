import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:eden_frontend/features/home/presentation/screens/contractor_jobs_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Booking job(
  int id, {
  JobStatus status = JobStatus.searching,
  String? dispatch,
  bool pin = true,
  String bookingType = 'one_time',
}) => Booking(
  id: id,
  property: Property(
    id,
    'Home $id',
    '$id Main Street, Lahore',
    'Large',
    '',
    pin: pin ? (latitude: 31.5 + id / 100, longitude: 74.3) : null,
  ),
  service: Service.snow,
  date: DateTime(2026, 11, 25),
  scheduledDate: '2026-11-25',
  total: 45,
  notes: '',
  status: status,
  dispatchStatus: dispatch,
  bookingType: bookingType,
);

void main() {
  test('available and active jobs map all saved customer pins alongside the self circle', () {
    for (final status in [JobStatus.searching, JobStatus.enRoute]) {
      final markers = contractorJobMarkers([job(1,status:status),job(2,status:status),job(3,pin:false)],position:(latitude:31.51,longitude:74.3));
      expect(markers.map((marker)=>marker['id']), ['self','job-1','job-2']);
      expect(markers.first['kind'], 'contractor');
      expect(markers[1]['kind'], status == JobStatus.searching ? 'customer' : 'active');
      expect(markers[1]['latitude'], job(1).property.pin!.latitude);
    }
  });
  test('only assigned long-term requests enter Available, and the empty map stays usable', () {
    final jobs = [job(1, bookingType:'long_term', dispatch:'pending_admin'), job(2, bookingType:'long_term', dispatch:'assigned'), job(3)];
    expect(contractorTabJobs(jobs, ContractorJobTab.available, true).map((job)=>job.id), [2,3]);
  });
  test('tabs partition jobs and include legacy pending requests as normal offers', () {
    final jobs = [
      job(1),
      job(2, dispatch: 'assigned'),
      job(3, dispatch: 'pending_admin'),
      job(4, status: JobStatus.enRoute),
      job(5, status: JobStatus.completed),
      job(6, status: JobStatus.cancelled),
    ];
    expect(
      contractorTabJobs(
        jobs,
        ContractorJobTab.available,
        true,
      ).map((job) => job.id),
      [1, 2, 3],
    );
    expect(
      contractorTabJobs(
        jobs,
        ContractorJobTab.available,
        false,
      ).map((job) => job.id),
      [2],
    );
    expect(contractorTabJobs(jobs, ContractorJobTab.active, true).single.id, 4);
    expect(
      contractorTabJobs(jobs, ContractorJobTab.completed, true).single.id,
      5,
    );
    expect(
      contractorTabJobs(jobs, ContractorJobTab.cancelled, true).single.id,
      6,
    );
  });

  for (final width in [360.0, 480.0]) {
    testWidgets(
      'cards, pins, overview and tabs stay synchronized at $width pixels',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final jobs = [
          job(1),
          job(2),
          job(3, status: JobStatus.accepted),
          job(4, status: JobStatus.completed),
        ];
        int? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ContractorJobsBrowser(
                    jobs: jobs,
                    available: true,
                    onAvailabilityChanged: (_) {},
                    onRefresh: () {},
                    onOpen: (job) => opened = job.id,
                    mapBuilder: (visible, selected, select) => Column(
                      children: [
                        Text(
                          'Map jobs: ${visible.map((job) => job.id).join(',')}',
                        ),
                        Text('Map selection: $selected'),
                        for (final job in visible)
                          TextButton(
                            key: Key('pin-${job.id}'),
                            onPressed: () => select(job.id),
                            child: Text('Pin ${job.id}'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Map jobs: 1,2'), findsOneWidget);
        await tester.tap(find.byKey(const Key('job-card-1')));
        await tester.pumpAndSettle();
        expect(find.text('Map selection: 1'), findsOneWidget);
        final expanded = tester.widget<AnimatedContainer>(
          find.byKey(const Key('contractor-jobs-map')),
        );
        expect(expanded.constraints!.maxHeight, 380);
        await tester.tap(find.byKey(const Key('pin-2')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Semantics>(find.byKey(const Key('job-card-2')))
              .properties
              .selected,
          true,
        );
        expect(find.text('Map selection: 2'), findsOneWidget);
        await tester.ensureVisible(find.text('View job details'));
        await tester.tap(find.text('View job details'));
        expect(opened, 2);
        await tester.ensureVisible(find.text('Show job pins'));
        await tester.tap(find.text('Show job pins'));
        await tester.pumpAndSettle();
        expect(find.text('Map selection: null'), findsOneWidget);
        await tester.ensureVisible(find.text('Active (1)'));
        await tester.tap(find.text('Active (1)'));
        await tester.pumpAndSettle();
        expect(find.text('Map jobs: 3'), findsOneWidget);
        expect(find.byKey(const Key('job-card-1')), findsNothing);
        await tester.tap(find.text('Completed (1)'));
        await tester.pumpAndSettle();
        expect(find.text('Map jobs: 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('jobs without pins remain usable without invented coordinates', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ContractorJobsBrowser(
              jobs: [job(1, pin: false)],
              available: true,
              onAvailabilityChanged: (_) {},
              onRefresh: () {},
              onOpen: (_) {},
              mapBuilder: (jobs, selected, select) {
                expect(jobs, isEmpty);
                return const Text('Map remains visible without job pins');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Map remains visible without job pins'), findsOneWidget);
    expect(find.byKey(const Key('job-card-1')), findsOneWidget);
  });
}
