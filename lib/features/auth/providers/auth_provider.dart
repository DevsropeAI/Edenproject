import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../domain/auth_state.dart';
import '../data/repositories/auth_repository.dart';

part 'auth_provider.g.dart';

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AuthState build() {
    // Keep the provider alive during async operations (like the 2-second login)
    ref.keepAlive();
    return const AuthState.initial();
  }

  Future<void> login(String email, String password) async {
    state = const AuthState.loading();
    try {
      final user = await ref.read(authRepositoryProvider).login(email, password);
      // Check if the provider is still alive before updating state
      if (ref.mounted) {
        state = AuthState.authenticated(user);
      }
    } catch (e) {
      if (ref.mounted) {
        state = AuthState.error(e.toString());
      }
    }
  }

  Future<void> register(String name, String email, String password, String role) async {
    state = const AuthState.loading();
    try {
      final user = await ref.read(authRepositoryProvider).register(name, email, password, role);
      if (ref.mounted) {
        state = AuthState.authenticated(user);
      }
    } catch (e) {
      if (ref.mounted) {
        state = AuthState.error(e.toString());
      }
    }
  }
}



// import 'package:riverpod_annotation/riverpod_annotation.dart';
// // import '../data/models/user.dart';
// import '../domain/auth_state.dart';
// import '../data/repositories/auth_repository.dart';

// part 'auth_provider.g.dart';

// @riverpod
// class AuthNotifier extends _$AuthNotifier {
//   @override
//   AuthState build() {
//     return const AuthState.initial();
//   }

//   Future<void> login(String email, String password) async {
//     state = const AuthState.loading();
//     try {
//       final user = await ref.read(authRepositoryProvider).login(email, password);
//       state = AuthState.authenticated(user);
//     } catch (e) {
//       state = AuthState.error(e.toString());
//     }
//   }

//   Future<void> register(String name, String email, String password, String role) async {
//     state = const AuthState.loading();
//     try {
//       final user = await ref.read(authRepositoryProvider).register(name, email, password, role);
//       state = AuthState.authenticated(user);
//     } catch (e) {
//       state = AuthState.error(e.toString());
//     }
//   }
// }