import 'package:flutter/material.dart';
import '../../../../core/theme/app_spacing.dart';

class BookingArrangementPicker extends StatelessWidget {
  const BookingArrangementPicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Service arrangement'),
      const SizedBox(height: EdenSpacing.gap),
      Wrap(spacing: EdenSpacing.gap, runSpacing: EdenSpacing.gap, children: [
        ChoiceChip(label: const Text('One-time service'), selected: value == 'one_time', onSelected: (_) => onChanged('one_time')),
        ChoiceChip(label: const Text('Long-term / recurring'), selected: value == 'long_term', onSelected: (_) => onChanged('long_term')),
      ]),
      const SizedBox(height: EdenSpacing.gap),
      Text(value == 'long_term' ? 'Eden will assign a contractor to your request. A repeat schedule is arranged separately.' : 'Your request is offered to all available contractors.'),
    ],
  );
}
