import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/providers/auth_provider.dart';
import 'address_search_field.dart';

final workLocationProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  if (ref.watch(activeAccountIdProvider) == null) return {};
  final response = await ref
      .watch(apiClientProvider)
      .get('/contractor/work-location');
  return Map<String, dynamic>.from(response.data as Map);
});

class WorkLocationEditor extends ConsumerStatefulWidget {
  const WorkLocationEditor({super.key});
  @override
  ConsumerState<WorkLocationEditor> createState() => _WorkLocationEditorState();
}

class _WorkLocationEditorState extends ConsumerState<WorkLocationEditor> {
  final _query = TextEditingController();
  Map<String, dynamic>? _selection;
  bool _saving = false;
  String? _message;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(workLocationProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: EdenSpacing.sm,
      children: [
        const SizedBox(height: EdenSpacing.section),
        const Text('Work location'),
        const SizedBox(height: EdenSpacing.sm),
        ...saved.when(
          loading: () => const [LinearProgressIndicator()],
          error: (_, _) => [
            TextButton(
              onPressed: () => ref.invalidate(workLocationProvider),
              child: const Text('Retry loading work location'),
            ),
          ],
          data: (data) => [
            Text('Existing service area: ${data['area'] ?? ''}'),
            if (data['city'] case final Map city)
              Text(
                'Saved city: ${[city['name'], city['state'], city['country']].whereType<String>().where((v) => v.isNotEmpty).join(', ')}',
              ),
          ],
        ),
        const SizedBox(height: EdenSpacing.screen),
        AddressSearchField(
          controller: _query,
          label: 'Search work city',
          enabled: !_saving,
          citiesOnly: true,
          onEdited: () => setState(() {
            _selection = null;
            _message = null;
          }),
          onSelected: (value) {
            if ((value['city'] as String? ?? '').isEmpty ||
                (value['country'] as String? ?? '').isEmpty) {
              setState(
                () => _message =
                    'Choose a result that includes a city and country.',
              );
              return;
            }
            setState(() {
              _message = null;
              _selection = value;
              _query.text = [
                value['city'],
                value['state'],
                value['country'],
              ].whereType<String>().where((v) => v.isNotEmpty).join(', ');
            });
          },
        ),
        const SizedBox(height: EdenSpacing.gap),
        if (_message != null) Text(_message!),
        FilledButton(
          onPressed: _selection == null || _saving
              ? null
              : () async {
                  setState(() {
                    _saving = true;
                    _message = null;
                  });
                  try {
                    await ref
                        .read(apiClientProvider)
                        .post(
                          '/contractor/work-location',
                          data: {'city': _selection},
                        );
                    ref.invalidate(workLocationProvider);
                    if (mounted) setState(() => _message = 'Work city saved.');
                  } catch (error) {
                    if (mounted) setState(() => _message = apiError(error));
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: const Text('Save work city'),
        ),
      ],
    );
  }
}
