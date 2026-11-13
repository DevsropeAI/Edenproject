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

  AuthRepository(this.apiClient, this._storage);

  Future<User> login(String email, String password) async {
    // Simulating API call for now since backend is not ready
    await Future.delayed(const Duration(seconds: 2)); 
    if (email.isEmpty || password.isEmpty) throw Exception('Invalid credentials');
    
    // Mock User
    final user = User(id: '1', email: email, name: 'Test User', role: 'customer');
    await _storage.saveToken('mock_jwt_token_123');
    return user;
  }

  Future<User> register(String name, String email, String password, String role) async {
    await Future.delayed(const Duration(seconds: 2));
    final user = User(id: '2', email: email, name: name, role: role);
    await _storage.saveToken('mock_jwt_token_123');
    return user;
  }
}