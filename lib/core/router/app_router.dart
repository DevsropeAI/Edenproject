import 'package:go_router/go_router.dart';

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

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/login',
    routes: [
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
          contractor: state.extra == true,
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
        builder: (context, state) =>
            ProfileScreen(contractor: state.extra == true),
      ),
    ],
  );
}
