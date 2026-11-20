import 'dart:js_interop';

@JS('navigator.wakeLock.request')
external JSPromise<JSObject> _request(String type);

extension type _Sentinel(JSObject _) implements JSObject {
  external JSPromise<JSAny?> release();
}

_Sentinel? _lock;
Future<bool> requestWalkingWakeLock() async {
  try {
    _lock = _Sentinel(await _request('screen').toDart);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> releaseWalkingWakeLock() async {
  final lock = _lock;
  _lock = null;
  try {
    await lock?.release().toDart;
  } catch (_) {}
}
