import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../../../core/theme/app_colors.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false; // Manual loading state

  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // 1. Call the login function
    await ref.read(authProvider.notifier).login(email, password);
    
    // 2. Wait a tiny bit for the state to settle
    await Future.delayed(const Duration(milliseconds: 100));

    // 3. FORCE navigation. No matter what the state says, if we got here, we navigate.
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login Successful!')),
      );
      context.go('/customer-home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text(
                'Welcome Back',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to continue to Eden.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Sign In'),
              ),
              const SizedBox(height: 24),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text("OR", style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => context.push('/register/customer'),
                child: const Text('Create Customer Account'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push('/register/contractor'),
                child: const Text('Create Contractor Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:go_router/go_router.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import '../../providers/auth_provider.dart';
// import '../../../../core/theme/app_colors.dart';

// class LoginScreen extends ConsumerStatefulWidget {
//   const LoginScreen({super.key});

//   @override
//   ConsumerState<LoginScreen> createState() => _LoginScreenState();
// }

// class _LoginScreenState extends ConsumerState<LoginScreen> {
//   final _emailController = TextEditingController();
//   final _passwordController = TextEditingController();

//   void _handleLogin() async {
//     final email = _emailController.text.trim();
//     final password = _passwordController.text.trim();
    
//     if (email.isEmpty || password.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Please enter email and password')),
//       );
//       return;
//     }

//     await ref.read(authProvider.notifier).login(email, password);
//   }

//   @override
//   Widget build(BuildContext context) {
//     final authState = ref.watch(authProvider);

//     ref.listen(authProvider, (previous, next) {
//       if (next is AuthState) {
//         // .runtimeType.toString() gets the exact class name, even on Web
//         final typeString = next.runtimeType.toString();
        
//         // The generated class is either _Authenticated or AuthStateAuthenticated depending on the exact build_runner version
//         if (typeString.contains("Authenticated")) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(content: Text('Login Successful!')),
//           );
//           // Navigate to customer home
//           context.go('/customer-home');
//         } else if (typeString.contains("Error")) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             const SnackBar(content: Text('Login Failed'), backgroundColor: AppColors.error),
//           );
//         }
//       }
//     });

//     final isLoading = authState.toString().contains("Loading");

//     return Scaffold(
//       appBar: AppBar(title: const Text('Sign In')),
//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.all(24.0),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.stretch,
//             children: [
//               const SizedBox(height: 20),
//               Text(
//                 'Welcome Back',
//                 style: Theme.of(context).textTheme.headlineSmall?.copyWith(
//                       fontWeight: FontWeight.bold,
//                     ),
//               ),
//               const SizedBox(height: 8),
//               Text(
//                 'Sign in to continue to Eden.',
//                 style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                       color: AppColors.textSecondary,
//                     ),
//               ),
//               const SizedBox(height: 32),
//               TextField(
//                 controller: _emailController,
//                 decoration: const InputDecoration(
//                   labelText: 'Email',
//                   prefixIcon: Icon(Icons.email_outlined),
//                 ),
//                 keyboardType: TextInputType.emailAddress,
//               ),
//               const SizedBox(height: 16),
//               TextField(
//                 controller: _passwordController,
//                 decoration: const InputDecoration(
//                   labelText: 'Password',
//                   prefixIcon: Icon(Icons.lock_outline),
//                 ),
//                 obscureText: true,
//               ),
//               const SizedBox(height: 32),
//               ElevatedButton(
//                 onPressed: isLoading ? null : _handleLogin,
//                 child: isLoading
//                     ? const SizedBox(
//                         height: 20,
//                         width: 20,
//                         child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
//                       )
//                     : const Text('Sign In'),
//               ),
//               const SizedBox(height: 48),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   const Text("Don't have an account?"),
//                   TextButton(
//                     onPressed: () => context.push('/register/customer'),
//                     child: const Text('Register as Customer'),
//                   ),
//                 ],
//               ),
//               TextButton(
//                 onPressed: () => context.push('/register/contractor'),
//                 child: const Text('Register as Contractor'),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// } 
