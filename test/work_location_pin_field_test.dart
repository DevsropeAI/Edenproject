import 'package:eden_frontend/features/home/presentation/screens/work_location_pin_field.dart';
import 'package:eden_frontend/features/home/presentation/screens/google_marketplace_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marketplace maps fit all markers by default', () {
    final canvas=GoogleMarketplaceCanvas(markers:const [],config:const {},onSelected:(_){});
    expect(canvas.fitAllMarkers,isTrue);
    expect(workPinFromJson({'latitude':91,'longitude':0}),isNull);
    expect(workPinFromJson({'latitude':31.5,'longitude':74}),(latitude:31.5,longitude:74.0));
  });
  for(final width in [360.0,480.0]) {
    testWidgets('work location pin validates, selects and displays at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width,800));
      addTearDown(()=>tester.binding.setSurfaceSize(null));
      final form=GlobalKey<FormState>();
      WorkPin? selected;
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:Padding(padding:const EdgeInsets.all(16),child:Form(key:form,child:StatefulBuilder(builder:(context,setState)=>WorkLocationPinField(value:selected,required:true,onChanged:(pin)=>setState(()=>selected=pin),pick:(_, _)async=>(latitude:31.5,longitude:74.3))))))));
      expect(form.currentState!.validate(),isFalse);
      await tester.pump();
      expect(find.text('Choose your work location on the map.'),findsOneWidget);
      await tester.tap(find.text('Choose work location on map'));
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(),isTrue);
      expect(selected,(latitude:31.5,longitude:74.3));
      expect(find.text('Selected pin: 31.50000, 74.30000'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }
}
