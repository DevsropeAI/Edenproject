import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final accountOptionsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    final response = await ref.watch(apiClientProvider).get('/auth/options');
    return Map<String, dynamic>.from(response.data as Map);
  },
);
