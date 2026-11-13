// import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/customer_register_screen.dart';
import '../../features/auth/presentation/screens/contractor_register_screen.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/onboarding',
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
    ],
  );
}