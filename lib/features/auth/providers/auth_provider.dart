import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/auth_state.dart';
import '../data/models/user.dart';
import '../data/repositories/auth_repository.dart';

part 'auth_provider.g.dart';

@riverpod
class AuthNotifier extends _$AuthNotifier {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    ref.keepAlive();
    unawaited(Future<void>.microtask(_restore));
    return const AuthState.initial();
  }

  Future<void> _restore() async {
    try {
      final account = await _repo.restore();
      if (!ref.mounted) return;
      if (account == null) {
        state = const AuthState.unauthenticated();
      } else {
        _apply(account);
      }
    } catch (error) {
      if (ref.mounted) state = AuthState.error(apiError(error));
    }
  }

  void _apply(Map<String, dynamic> account) {
    ref.read(registrationDetailsProvider.notifier).save(account);
    state = AuthState.authenticated(User.fromJson(account));
  }

  Future<void> logout() async {
    await _repo.logout();
    if (!ref.mounted) return;
    ref.invalidate(registrationDetailsProvider);
    state = const AuthState.unauthenticated();
  }

  Future<void> login(String email, String password) async {
    state = const AuthState.loading();
    try {
      final account = await _repo.login(email, password);
      if (ref.mounted) _apply(account);
    } catch (error) {
      if (ref.mounted) state = AuthState.error(apiError(error));
    }
  }

  Future<void> register(Map<String, dynamic> details) async {
    state = const AuthState.loading();
    try {
      await _repo.register(details);
      if (ref.mounted) state = const AuthState.unauthenticated();
    } catch (error) {
      if (ref.mounted) state = AuthState.error(apiError(error));
    }
  }

  Future<void> switchMode(String role, {String? area, String? service}) async {
    final account = await _repo.update('mode', {
      'role': role,
      'area': area,
      'service': service,
    });
    if (ref.mounted) _apply(account);
  }

  Future<void> updateProfile(User user, String phone) async {
    final account = await _repo.update('profile', {
      'name': user.name,
      'phone': phone,
    });
    if (ref.mounted) _apply(account);
  }

  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    if (!ref.mounted) return;
    ref.invalidate(registrationDetailsProvider);
    state = const AuthState.unauthenticated();
  }
}

final activeAccountIdProvider = Provider<String?>(
  (ref) => ref.watch(
    authProvider.select(
      (auth) =>
          auth.maybeWhen(authenticated: (user) => user.id, orElse: () => null),
    ),
  ),
);

typedef RegistrationDetails = ({String phone, String area, String service});

final registrationDetailsProvider =
    NotifierProvider<RegistrationDetailsNotifier, RegistrationDetails>(
      RegistrationDetailsNotifier.new,
    );

class RegistrationDetailsNotifier extends Notifier<RegistrationDetails> {
  @override
  RegistrationDetails build() => (phone: '', area: '', service: '');

  void save(Map<String, dynamic> account) {
    state = (
      phone: account['phone'] as String,
      area: account['area'] as String,
      service: account['service'] as String,
    );
  }
}
