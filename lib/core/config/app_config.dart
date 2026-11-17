import 'package:flutter/foundation.dart';

class AppConfig {
  static const String appName = 'Eden';
  static const _configuredUrl = String.fromEnvironment('EDEN_API_URL');

  static String get apiBaseUrl => _configuredUrl.isNotEmpty
      ? _configuredUrl
      : !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? 'http://172.16.1.2:3001/api'
      : 'http://localhost:3001/api';
}
