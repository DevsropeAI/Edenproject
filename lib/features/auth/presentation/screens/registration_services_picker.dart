import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

String registrationPrimaryTitle(
  List<Map<String, dynamic>> services,
  String current,
) =>
    (services
                .where(
                  (service) =>
                      (service['title'] as String).toLowerCase() ==
                      current.toLowerCase(),
                )
                .firstOrNull ??
            services.firstOrNull)?['title']
        as String? ??
    '';

class RegistrationServicesPicker extends StatelessWidget {
  const RegistrationServicesPicker({
    super.key,
    required this.services,
    required this.primary,
    required this.additionalIds,
    required this.onPrimaryChanged,
    required this.onAdditionalChanged,
    this.enabled = true,
    this.supportsAdditional = true,
  });
  final List<Map<String, dynamic>> services;
  final String primary;
  final Set<String> additionalIds;
  final ValueChanged<String> onPrimaryChanged;
  final ValueChanged<Set<String>> onAdditionalChanged;
  final bool enabled;
  final bool supportsAdditional;

  @override
  Widget build(BuildContext context) {
    final selected = registrationPrimaryTitle(services, primary);
    final primaryId = services
        .where((service) => service['title'] == selected)
        .firstOrNull?['id'];
    final additional = services
        .where((service) => service['id'] != primaryId)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(
            'primary:$selected:${services.map((service) => service['id']).join(',')}',
          ),
          initialValue: selected.isEmpty ? null : selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Primary service'),
          validator: (value) => value == null || value.isEmpty
              ? 'Choose a primary service.'
              : null,
          items: [
            for (final service in services)
              DropdownMenuItem(
                value: service['title'] as String,
                child: Text(
                  service['title'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onPrimaryChanged(value);
                }
              : null,
        ),
        const SizedBox(height: EdenSpacing.section),
        Text(
          'Additional services',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: EdenSpacing.sm),
        Text(
          supportsAdditional
              ? 'Choose every other service you offer. You can change these later in your profile.'
              : 'Update or restart the backend to select additional services during registration.',
        ),
        if (supportsAdditional) ...[
          const SizedBox(height: EdenSpacing.gap),
          Wrap(
            spacing: EdenSpacing.sm,
            runSpacing: EdenSpacing.sm,
            children: [
              for (final service in additional)
                FilterChip(
                  key: ValueKey('registration-service-${service['id']}'),
                  label: Text(service['title'] as String),
                  selected: additionalIds.contains(service['id']),
                  onSelected: enabled
                      ? (value) {
                          final next = {...additionalIds};
                          if (value) {
                            next.add(service['id'] as String);
                          } else {
                            next.remove(service['id']);
                          }
                          onAdditionalChanged(next);
                        }
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
