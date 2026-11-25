import '../../features/home/presentation/screens/explore_services_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/domain/auth_state.dart';

import '../../features/home/presentation/screens/account_extras_screen.dart';

import '../../features/home/presentation/screens/integration_demo_screen.dart';

import '../../features/home/presentation/screens/profile_tools.dart';

import '../../features/home/presentation/screens/demo_settings_screen.dart';

import '../../features/auth/presentation/screens/account_form_screen.dart';

import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/customer_register_screen.dart';
import '../../features/auth/presentation/screens/contractor_register_screen.dart';
import '../../features/home/presentation/screens/customer_home_screen.dart';
import '../../features/home/presentation/screens/contractor_home_screen.dart';

import '../../features/home/marketplace.dart';
import '../../features/home/presentation/screens/marketplace_screens.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;
      final isPublic =
          path == '/login' ||
          path == '/onboarding' ||
          path == '/reset-password' ||
          path.startsWith('/register/');
      final role = ref
          .read(authProvider)
          .maybeWhen(authenticated: (user) => user.role, orElse: () => null);
      if (role == null) return isPublic ? null : '/login';
      final home = '/$role-home';
      if (isPublic) return home;
      final customerOnly =
          path == '/customer-home' ||
          path == '/explore-services' ||
          path == '/bookings' ||
          path.startsWith('/bookings/') ||
          path == '/properties' ||
          path.startsWith('/booking/') ||
          path == '/settings/automatic' ||
          path == '/account/payments' ||
          path == '/account/recurring';
      final contractorOnly =
          path == '/contractor-home' ||
          path.startsWith('/job-details/') ||
          path == '/verification' ||
          path == '/settings/wallet' ||
          path == '/settings/verification' ||
          path == '/account/schedule';
      if ((role == 'customer' && contractorOnly) ||
          (role == 'contractor' && customerOnly)) {
        return home;
      }
      return null;
    },
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/account/:section',
        builder: (context, state) {
          final section = AccountSection.values
              .where((value) => value.name == state.pathParameters['section'])
              .firstOrNull;
          return section == null
              ? const ProfileScreen()
              : AccountExtrasScreen(section: section);
        },
      ),
      GoRoute(
        path: '/integration-demo',
        builder: (context, state) => const IntegrationDemoScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) =>
            const AccountFormScreen(mode: AuthMode.reset),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/register/customer',
        builder: (context, state) => const CustomerRegisterScreen(),
      ),
      GoRoute(
        path: '/register/contractor',
        builder: (context, state) => const ContractorRegisterScreen(),
      ),
      GoRoute(path: '/explore-services', builder: (context, state) => const ExploreServicesScreen()),
      GoRoute(
        path: '/customer-home',
        builder: (context, state) => const CustomerHomeScreen(),
      ),
      GoRoute(
        path: '/contractor-home',
        builder: (context, state) => const ContractorHomeScreen(),
      ),
      GoRoute(
        path: '/properties',
        builder: (context, state) =>
            PropertiesScreen(service: state.extra as Service?),
      ),
      GoRoute(
        path: '/booking/:id',
        builder: (context, state) => BookingScreen(
          propertyId: int.tryParse(state.pathParameters['id']!),
          service: state.extra as Service?,
        ),
      ),
      GoRoute(
        path: '/bookings',
        builder: (context, state) => const BookingListScreen(),
      ),
      GoRoute(
        path: '/bookings/:id',
        builder: (context, state) =>
            BookingDetailsScreen(id: int.tryParse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/job-details/:id',
        builder: (context, state) => BookingDetailsScreen(
          id: int.tryParse(state.pathParameters['id']!),
          contractor: true,
        ),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) => ChatScreen(
          id: int.tryParse(state.pathParameters['id']!),
          contractor: ref
              .read(authProvider)
              .maybeWhen(
                authenticated: (user) => user.role == 'contractor',
                orElse: () => false,
              ),
        ),
      ),
      GoRoute(
        path: '/settings/:section',
        builder: (context, state) {
          final section = SettingsSection.values
              .where(
                (section) => section.name == state.pathParameters['section'],
              )
              .firstOrNull;
          return section == null
              ? const ProfileScreen()
              : DemoSettingsScreen(section: section);
        },
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/verification',
        builder: (context, state) => const VerificationScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => ProfileScreen(
          contractor: ref
              .read(authProvider)
              .maybeWhen(
                authenticated: (user) => user.role == 'contractor',
                orElse: () => false,
              ),
        ),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
