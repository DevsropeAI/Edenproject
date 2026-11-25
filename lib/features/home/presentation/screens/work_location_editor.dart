import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/providers/auth_provider.dart';
import 'work_location_pin_field.dart';

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
  WorkPin? _selection;
  bool _saving = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(workLocationProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: EdenSpacing.sm,
      children: [
        const SizedBox(height: EdenSpacing.section),
        if (saved.isLoading) const LinearProgressIndicator(),
        if (saved.hasError) TextButton(onPressed:()=>ref.invalidate(workLocationProvider),child:const Text('Retry loading work location')),
        if (saved.hasValue) WorkLocationPinField(value:_selection ?? workPinFromJson(saved.value?['workPin']),enabled:!_saving,onChanged:(pin)=>setState((){_selection=pin;_message=null;})),
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
                          data: {'workPin': {'latitude':_selection!.latitude,'longitude':_selection!.longitude}},
                        );
                    ref.invalidate(workLocationProvider);
                    if (mounted) setState(() => _message = 'Work location saved.');
                  } catch (error) {
                    if (mounted) setState(() => _message = apiError(error));
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: const Text('Save work location'),
        ),
      ],
    );
  }
}
