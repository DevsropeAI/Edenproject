import 'package:eden_frontend/features/home/presentation/screens/marketplace_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 480.0]) {
    testWidgets('map controls and legend fit at $width pixels', (tester) async {
      tester.view.resetPhysicalSize();
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            marketplaceMapProvider.overrideWith(
              (ref) async => {
                'notice': 'Exact pins stay hidden until acceptance.',
                'markers': <Map<String, dynamic>>[],
                'config': {
                  for (final kind in [
                    'customer',
                    'large',
                    'contractor',
                    'active',
                    'completed',
                  ])
                    kind: {
                      'color': kind == 'contractor' ? '#3B82F6' : '#E8412C',
                      'shape': kind == 'contractor' ? 'circle' : 'pin',
                      'size': 44,
                      if (kind == 'large') 'badge': 'L',
                    },
                },
              },
            ),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: MarketplaceMap(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Large open lead'), findsNothing);
      await tester.tap(find.text('Map key'));
      await tester.pumpAndSettle();
      expect(find.text('Large open lead'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('Large open lead'), findsNothing);
    });
  }
}
