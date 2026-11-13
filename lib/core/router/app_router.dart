import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/customer_register_screen.dart';
import '../../features/auth/presentation/screens/contractor_register_screen.dart';
import '../../features/home/presentation/screens/customer_home_screen.dart';
import '../../features/home/presentation/screens/contractor_home_screen.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/login', 
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
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
    ],
  );
}