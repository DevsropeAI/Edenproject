import 'dart:async';

import 'package:dio/dio.dart';
import 'package:eden_frontend/core/network/api_client.dart';
import 'package:eden_frontend/core/storage/secure_storage.dart';
import 'package:eden_frontend/features/home/presentation/screens/address_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class SearchApi extends ApiClient {
  SearchApi() : super(SecureStorage());
  final calls = <({String path, Map<String, dynamic> params})>[];
  Completer<Response>? pendingDetails;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    calls.add((path: path, params: queryParameters ?? {}));
    if (path.endsWith('place') && pendingDetails != null) {
      return pendingDetails!.future;
    }
    return Response(
      requestOptions: RequestOptions(path: path),
      data: path.endsWith('place')
          ? {
              'label': 'Lahore, Punjab, Pakistan',
              'city': 'Lahore',
              'country': 'Pakistan',
              'latitude': 31.5,
              'longitude': 74.3,
            }
          : [
              {
                'label': 'Lahore, Punjab, Pakistan',
                'placeId': 'ChIJTest',
                'needsDetails': true,
              },
            ],
    );
  }
}

void main() {
  for (final registration in [false, true]) {
    testWidgets(
      'Google predictions resolve only after selection (${registration ? 'registration' : 'signed in'})',
      (tester) async {
        final api = SearchApi();
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        Map<String, dynamic>? selected;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(api),
              geoCapabilitiesProvider.overrideWith(
                (ref) async => {
                  'autocomplete': true,
                  'search': true,
                  'attribution': 'Google Maps',
                },
              ),
              registrationCityCapabilitiesProvider.overrideWith(
                (ref) async => {
                  'autocomplete': true,
                  'search': true,
                  'attribution': 'Google Maps',
                },
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Form(
                    child: AddressSearchField(
                      controller: controller,
                      label: 'Work city',
                      citiesOnly: true,
                      registration: registration,
                      onSelected: (value) => selected = value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Lahore');
        await tester.pump(const Duration(milliseconds: 399));
        expect(api.calls, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pumpAndSettle();
        expect(api.calls.length, 1);
        expect(
          api.calls.first.path,
          registration ? '/auth/work-city-autocomplete' : '/geo/autocomplete',
        );
        expect(selected, isNull);
        expect(find.text('Google Maps'), findsOneWidget);
        await tester.tap(find.text('Lahore, Punjab, Pakistan'));
        await tester.pumpAndSettle();
        expect(
          api.calls.last.path,
          registration ? '/auth/work-city-place' : '/geo/place',
        );
        expect(
          api.calls.last.params['sessionToken'],
          api.calls.first.params['sessionToken'],
        );
        expect(api.calls.last.params['type'], 'city');
        expect(selected?['city'], 'Lahore');
        expect(selected?['latitude'], 31.5);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'editing while Google details load discards the stale selection',
    (tester) async {
      final api = SearchApi();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      Map<String, dynamic>? selected;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            geoCapabilitiesProvider.overrideWith(
              (ref) async => {
                'autocomplete': true,
                'attribution': 'Google Maps',
              },
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AddressSearchField(
                controller: controller,
                label: 'Address',
                onSelected: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Lahore');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      api.pendingDetails = Completer<Response>();
      await tester.tap(find.text('Lahore, Punjab, Pakistan'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'New address');
      api.pendingDetails!.complete(
        Response(
          requestOptions: RequestOptions(path: '/geo/place'),
          data: {'city': 'Lahore'},
        ),
      );
      await tester.pump();
      expect(selected, isNull);
      expect(controller.text, 'New address');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
