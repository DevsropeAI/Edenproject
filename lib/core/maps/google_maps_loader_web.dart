import 'dart:js_interop';

@JS('edenLoadGoogleMaps')
external JSPromise<JSAny?> _loadGoogleMaps();

Future<void> loadGoogleMaps() async {
  await _loadGoogleMaps().toDart;
}
