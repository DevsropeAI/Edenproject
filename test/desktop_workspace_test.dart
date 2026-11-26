import 'package:eden_frontend/core/theme/app_dark_theme.dart';
import 'package:eden_frontend/core/widgets/desktop_workspace.dart';
import 'package:eden_frontend/core/widgets/glass_controls.dart';
import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:eden_frontend/features/home/presentation/screens/customer_desktop_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  test('desktop layout is wide-web only; native apps and phone browsers stay mobile', () {
    expect(EdenDesktopLayout.forWidth(1920, web: false), isFalse);
    expect(EdenDesktopLayout.forWidth(390, web: true), isFalse);
    expect(EdenDesktopLayout.forWidth(1024, web: true), isFalse);
    expect(EdenDesktopLayout.forWidth(1100, web: true), isTrue);
    expect(EdenDesktopLayout.forWidth(1440, web: true), isTrue);
  });
  for (final width in [1100.0, 1440.0, 1920.0]) {
    testWidgets(
      'customer workspace fits $width with sidebar, real totals and navigation',
      (tester) async {
        GoogleFonts.config.allowRuntimeFetching = false;
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        String? destination;
        final bookings = [
          for (final status in [
            JobStatus.searching,
            JobStatus.accepted,
            JobStatus.completed,
          ])
            Booking(
              id: status.index,
              property: const Property(1, 'Home', 'Lahore', 'Large', ''),
              service: Service.snow,
              date: DateTime(2026, 11, 26),
              total: 45,
              notes: '',
              status: status,
            ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: EdenDarkTheme.data,
            home: EdenDesktopWorkspace(
              title: 'Overview',
              role: 'customer',
              name: 'Customer',
              currentPath: '/customer-home',
              onNavigate: (path) => destination = path,
              children: [
                CustomerDesktopOverview(
                  bookings: bookings,
                  onExplore: () => destination = '/explore-services',
                  onProperties: () => destination = '/properties',
                ),
                EdenDesktopGrid(
                  children: [
                    for (final id in [1, 2, 3])
                      GlassCard(
                        key: ValueKey('grid-$id'),
                        child: Text('Booking $id'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('desktop-workspace')), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.text('New bookings'), findsOneWidget);
        expect(find.text('In progress'), findsOneWidget);
        expect(
          tester.getSize(find.byType(EdenDesktopGrid).first).width,
          greaterThan(480),
        );
        await tester.tap(find.text('Orders'));
        expect(destination, '/bookings');
        await tester.tap(find.text('Explore services').last);
        expect(destination, '/explore-services');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('contractor sidebar uses existing contractor destinations', (
    tester,
  ) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? destination;
    await tester.pumpWidget(
      MaterialApp(
        theme: EdenDarkTheme.data,
        home: EdenDesktopWorkspace(
          title: 'Jobs',
          role: 'contractor',
          currentPath: '/job-details/1',
          onNavigate: (path) => destination = path,
          children: const [Text('Existing job content')],
        ),
      ),
    );
    expect(find.text('Properties'), findsNothing);
    await tester.tap(find.text('Earnings'));
    expect(destination, '/settings/wallet');
    await tester.tap(find.text('Support & messages'));
    expect(destination, '/settings/support');
    expect(tester.takeException(), isNull);
  });
}
