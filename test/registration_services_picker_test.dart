import 'package:eden_frontend/features/auth/presentation/screens/registration_services_picker.dart';
import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:eden_frontend/features/home/presentation/screens/marketplace_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'all services are selectable at registration and multiple choices stay selected',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final services = [
        for (final service in Service.values)
          {'id': service.name, 'title': service.label},
      ];
      var primary = 'Snow removal';
      var selected = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: StatefulBuilder(
                  builder: (context, update) => RegistrationServicesPicker(
                    services: services,
                    primary: primary,
                    additionalIds: selected,
                    onPrimaryChanged: (value) => update(() => primary = value),
                    onAdditionalChanged: (value) =>
                        update(() => selected = value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(FilterChip), findsNWidgets(16));
      for (final id in ['lawn', 'tree']) {
        await tester.ensureVisible(
          find.byKey(ValueKey('registration-service-$id')),
        );
        await tester.tap(find.byKey(ValueKey('registration-service-$id')));
        await tester.pumpAndSettle();
      }
      expect(selected, {'lawn', 'tree'});
      expect(registrationPrimaryTitle(services, primary), 'Snow Removal');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'job requirements show instructions, yards, driveway and walkway even before acceptance',
    (tester) async {
      final booking = Booking(
        id: 1,
        service: Service.lawn,
        date: DateTime(2026, 11, 25),
        total: 30,
        notes: 'Mow the front and back lawns',
        property: const Property(
          1,
          'Home',
          'Main Street',
          'Large',
          'Use side entrance',
          measurements: {
            'driveway': 'large',
            'walkway': 'long',
            'frontYard': true,
            'frontYardSize': '',
            'backyard': true,
            'backyardSize': '300 sq ft',
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: JobRequirements(booking))),
      );
      expect(find.text('Use side entrance'), findsOneWidget);
      expect(find.text('Mow the front and back lawns'), findsOneWidget);
      expect(find.text('Front yard: Yes'), findsOneWidget);
      expect(find.text('Backyard: Yes · 300 sq ft'), findsOneWidget);
      expect(find.text('Walkway: long'), findsOneWidget);
      expect(find.text('Driveway: large'), findsOneWidget);
    },
  );
}
