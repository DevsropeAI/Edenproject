import 'package:eden_frontend/core/widgets/desktop_workspace.dart';
import 'package:eden_frontend/features/auth/domain/auth_state.dart';
import 'package:eden_frontend/features/auth/providers/auth_provider.dart';
import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:eden_frontend/features/home/presentation/screens/customer_home_screen.dart';
import 'package:eden_frontend/features/home/presentation/screens/marketplace_screens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class BrowserAuth extends AuthNotifier {
  @override
  AuthState build() => const AuthState.unauthenticated();
}

class BrowserBookings extends Bookings {
  @override
  List<Booking> build() => [
    for (final id in [1, 2])
      Booking(
        id: id,
        property: const Property(1, 'Home', 'Main Street', 'Large', ''),
        service: Service.snow,
        date: DateTime(2026, 11, 26),
        total: 45,
        notes: '',
        status: JobStatus.accepted,
      ),
  ];
}

void main() {
  testWidgets(
    'real browser pages use a sidebar and booking grid, then return to mobile on resize',
    (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = GoRouter(
        initialLocation: '/customer-home',
        routes: [
          GoRoute(
            path: '/customer-home',
            builder: (_, _) => const CustomerHomeScreen(),
          ),
          GoRoute(
            path: '/bookings',
            builder: (_, _) => const BookingListScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(BrowserAuth.new),
            bookingsProvider.overrideWith(BrowserBookings.new),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(EdenDesktopWorkspace), findsOneWidget);
      expect(find.byType(CustomerNavigation), findsNothing);
      final first = find.byKey(const ValueKey('customer-booking-1'));
      final second = find.byKey(const ValueKey('customer-booking-2'));
      await tester.ensureVisible(first);
      expect(
        tester.getTopLeft(second).dx,
        greaterThan(tester.getTopLeft(first).dx),
      );
      expect(tester.getTopLeft(second).dy, tester.getTopLeft(first).dy);
      await tester.tap(find.text('Orders'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.routeInformationProvider.value.uri.path, '/bookings');
      await tester.binding.setSurfaceSize(const Size(390, 900));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(EdenDesktopWorkspace), findsNothing);
      expect(find.byType(CustomerNavigation), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !kIsWeb,
  );
}
