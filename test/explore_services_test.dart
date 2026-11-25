import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:eden_frontend/features/home/presentation/screens/customer_home_screen.dart';
import 'package:eden_frontend/features/home/presentation/screens/explore_services_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class IdleBookings extends Bookings {
  @override
  List<Booking> build() => [];
}

void main() {
  for (final width in [360.0, 480.0]) {
    testWidgets('home opens separate dynamic services page at $width', (tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = Service.fromId('custom', title: 'Window Cleaning');
      final router = GoRouter(routes: [
        GoRoute(path:'/',builder:(_, _)=>const CustomerHomeScreen()),
        GoRoute(path:'/explore-services',builder:(_, _)=>const ExploreServicesScreen()),
        GoRoute(path:'/properties',builder:(_, state)=>Text('Selected ${((state.extra as Service?)?.name)}')),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        bookingsProvider.overrideWith(IdleBookings.new),
        serviceCatalogProvider.overrideWith((_)async=>{service:7500}),
        serviceDetailsProvider.overrideWith((_)async=>[{'id':'custom','title':'Window Cleaning','description':'Windows'}]),
      ],child:MaterialApp.router(routerConfig:router)));
      await tester.pump(const Duration(milliseconds:500));
      expect(find.text('Window Cleaning'), findsNothing);
      await tester.tap(find.text('Explore services').first);
      await tester.pump(const Duration(milliseconds:500));
      await tester.pump(const Duration(milliseconds:500));
      expect(find.text('Window Cleaning'),findsOneWidget);
      await tester.ensureVisible(find.text('Window Cleaning'));
      await tester.tap(find.text('Window Cleaning'));
      await tester.pump(const Duration(milliseconds:500));
      await tester.pump(const Duration(milliseconds:500));
      expect(find.text('Selected custom'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }
}
