import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../models/user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(apiClientProvider), SecureStorage());
});

class AuthRepository {
  final ApiClient apiClient;
  final SecureStorage _storage;
  final _demoAccounts = <String, ({User user, String password})>{};
  final _deletedEmails = <String>{};

  AuthRepository(this.apiClient, this._storage);

  Future<User> login(String email, String password) async {
    // Simulating API call for now since backend is not ready
    await Future.delayed(const Duration(seconds: 2));
    if (email.isEmpty || password.isEmpty) {
      throw Exception('Invalid credentials');
    }

    // Mock User
    final key = email.toLowerCase();
    if (_deletedEmails.contains(key)) {
      throw Exception('Account deleted. Create a new account to continue.');
    }
    final account = _demoAccounts[key];
    if (account != null && account.password != password) {
      throw Exception('Incorrect password');
    }
    final user =
        account?.user ??
        User(id: '1', email: email, name: 'Test User', role: 'customer');
    await _storage.saveToken('mock_jwt_token_123');
    return user;
  }

  Future<void> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    await Future.delayed(const Duration(seconds: 2));
    final key = email.toLowerCase();
    if (_demoAccounts.containsKey(key)) {
      throw Exception('An account already uses this email');
    }
    await _storage.deleteToken();
    if (_demoAccounts.containsKey(key)) {
      throw Exception('An account already uses this email');
    }
    _demoAccounts[key] = (
      user: User(id: key, email: email, name: name, role: role),
      password: password,
    );
    _deletedEmails.remove(key);
  }

  void updateProfile(User user) {
    final key = user.email.toLowerCase();
    final account = _demoAccounts[key];
    if (account != null) {
      _demoAccounts[key] = (user: user, password: account.password);
    }
  }

  Future<void> deleteAccount(String email) async {
    await _storage.deleteToken();
    final key = email.toLowerCase();
    _demoAccounts.remove(key);
    _deletedEmails.add(key);
  }
}
