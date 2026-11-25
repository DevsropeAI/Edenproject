import 'package:eden_frontend/features/home/presentation/screens/booking_arrangement_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 480.0]) {
    testWidgets('booking arrangement choices fit and explain assignment at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var value = 'one_time';
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: StatefulBuilder(builder: (context, setState) => BookingArrangementPicker(value: value, onChanged: (next) => setState(() => value = next)))))));
      expect(find.text('Your request is offered to all available contractors.'), findsOneWidget);
      await tester.tap(find.text('Long-term / recurring'));
      await tester.pumpAndSettle();
      expect(value, 'long_term');
      expect(find.textContaining('Eden will assign'), findsOneWidget);
      await tester.tap(find.text('One-time service'));
      await tester.pumpAndSettle();
      expect(value, 'one_time');
      expect(tester.takeException(), isNull);
    });
  }
}
