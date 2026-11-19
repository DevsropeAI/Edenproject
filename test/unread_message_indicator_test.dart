import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:eden_frontend/features/home/presentation/screens/marketplace_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final contractor in [false, true]) {
    testWidgets(
      'unread indicator clears for ${contractor ? 'contractor' : 'customer'} after reading',
      (tester) async {
        Booking booking(int read) => Booking(
          id: 1,
          property: const Property(
            1,
            'Home',
            'Main St, Lahore',
            'Standard',
            '',
          ),
          service: Service.snow,
          date: DateTime(2026, 11, 20),
          total: 45,
          notes: '',
          messages: const [
            (contractor: false, text: 'Customer message', image: null),
            (contractor: true, text: 'Contractor message', image: null),
          ],
          customerRead: read,
          contractorRead: read,
        );

        Future<void> show(int read) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BookingMessageButton(
                booking: booking(read),
                contractor: contractor,
              ),
            ),
          ),
        );

        await show(0);
        expect(find.byIcon(Icons.circle), findsOneWidget);
        await show(2);
        expect(find.byIcon(Icons.circle), findsNothing);
        expect(find.text('Messages'), findsOneWidget);
      },
    );
  }
}
