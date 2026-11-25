import 'dart:typed_data';
import 'package:eden_frontend/features/home/marketplace.dart';
import 'package:eden_frontend/features/home/presentation/screens/address_search_field.dart';
import 'package:eden_frontend/features/home/presentation/screens/marketplace_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class PinProperties extends Properties {
  String? savedAddress;
  ({double latitude, double longitude})? savedPin;
  @override
  List<Property> build() => [const Property(1,'Home','Street, Lahore','Large','',pin:(latitude:31.5,longitude:74.3),structuredAddress:{'street':'Street','city':'Lahore','country':'Pakistan'})];
  @override
  Future<bool> save(int? id,String name,String address,String size,String notes,{required String type,Uint8List? photo,({double latitude,double longitude})? pin,Map<String,dynamic>? structuredAddress,Map<String,dynamic>? measurements,Map<String,dynamic>? addressSelection}) async {
    savedAddress=address;
    savedPin=pin;
    return true;
  }
}

void main() {
  testWidgets('property form hides separate street/city and saves a pin with optional correction empty', (tester) async {
    GoogleFonts.config.allowRuntimeFetching=false;
    final records=PinProperties();
    await tester.binding.setSurfaceSize(const Size(480,1000));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(overrides:[propertiesProvider.overrideWith(()=>records),geoCapabilitiesProvider.overrideWith((_)async=>{'structuredAddresses':true})],child:const MaterialApp(home:PropertiesScreen())));
    await tester.pump(const Duration(milliseconds:500));
    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await tester.pump(const Duration(milliseconds:500));
    await tester.pump(const Duration(milliseconds:500));
    expect(find.text('Street address'),findsNothing);
    expect(find.text('City'),findsNothing);
    final correction=find.byWidgetPredicate((widget)=>widget is TextFormField && widget.controller?.text=='Street, Lahore');
    await tester.ensureVisible(correction);
    await tester.enterText(correction,'');
    await tester.tap(find.text('Save property'));
    await tester.pump(const Duration(milliseconds:500));
    expect(records.savedPin,(latitude:31.5,longitude:74.3));
    expect(records.savedAddress,'Pinned location (31.5, 74.3)');
    expect(tester.takeException(),isNull);
  });
}
