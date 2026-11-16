import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/storage/secure_storage.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(apiClientProvider), SecureStorage());
});

String apiError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String)
      return data['message'] as String;
    return 'Could not reach Eden. Check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}

class AuthRepository {
  final ApiClient apiClient;
  final SecureStorage _storage;

  AuthRepository(this.apiClient, this._storage);

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await apiClient.post(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    await _storage.saveToken(response.data['token'] as String);
    return Map<String, dynamic>.from(response.data['user'] as Map);
  }

  Future<Map<String, dynamic>?> restore() async {
    if (await _storage.getToken() == null) return null;
    try {
      final response = await apiClient.get('/auth/me');
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
      await _storage.deleteToken();
      return null;
    }
  }

  Future<void> register(Map<String, dynamic> details) async {
    await apiClient.post('/auth/register', data: details);
  }

  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async {
    final response = await apiClient.post('/auth/$path', data: data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> logout() async {
    try {
      await apiClient.post('/auth/logout');
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) rethrow;
    }
    await _storage.deleteToken();
  }

  Future<void> deleteAccount() async {
    await apiClient.delete('/auth/me');
    await _storage.deleteToken();
  }
}
