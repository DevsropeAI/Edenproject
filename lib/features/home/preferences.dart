import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../auth/providers/auth_provider.dart';
import 'marketplace.dart';

final preferencesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  if (ref.watch(activeAccountIdProvider) == null) return {};
  final response = await ref.watch(apiClientProvider).get('/preferences');
  return Map<String, dynamic>.from(response.data as Map);
});

Future<void> savePreferences(Ref ref, Map<String, dynamic> changes) async {
  try {
    await ref.read(apiClientProvider).post('/preferences', data: changes);
    if (ref.mounted) ref.invalidate(preferencesProvider);
  } catch (error) {
    if (ref.mounted) {
      ref.read(marketplaceFeedbackProvider.notifier).report(error);
      ref.invalidate(preferencesProvider);
    }
  }
}
