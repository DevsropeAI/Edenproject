import 'package:flutter_riverpod/flutter_riverpod.dart'
    show Notifier, NotifierProvider;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/auth_state.dart';
import '../data/models/user.dart';
import '../data/repositories/auth_repository.dart';

import '../../../core/storage/secure_storage.dart';

part 'auth_provider.g.dart';

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AuthState build() {
    // Keep the provider alive during async operations (like the 2-second login)
    ref.keepAlive();
    return const AuthState.initial();
  }

  Future<void> logout() async {
    await SecureStorage().deleteToken();
    if (ref.mounted) state = const AuthState.unauthenticated();
  }

  Future<void> login(String email, String password) async {
    state = const AuthState.loading();
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .login(email, password);
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

  Future<void> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    state = const AuthState.loading();
    try {
      await ref
          .read(authRepositoryProvider)
          .register(name, email, password, role);
      if (ref.mounted) {
        state = const AuthState.unauthenticated();
      }
    } catch (e) {
      if (ref.mounted) {
        state = AuthState.error(e.toString());
      }
    }
  }

  void updateProfile(User user) {
    ref.read(authRepositoryProvider).updateProfile(user);
    state = AuthState.authenticated(user);
  }

  Future<void> deleteAccount(String email) async {
    await ref.read(authRepositoryProvider).deleteAccount(email);
    if (ref.mounted) state = const AuthState.unauthenticated();
  }
}

typedef RegistrationDetails = ({String phone, String area, String service});

final registrationDetailsProvider =
    NotifierProvider<RegistrationDetailsNotifier, RegistrationDetails>(
      RegistrationDetailsNotifier.new,
    );

class RegistrationDetailsNotifier extends Notifier<RegistrationDetails> {
  @override
  RegistrationDetails build() => (phone: '', area: '', service: '');

  void save({
    required String phone,
    required String area,
    required String service,
  }) {
    state = (phone: phone, area: area, service: service);
  }
}
