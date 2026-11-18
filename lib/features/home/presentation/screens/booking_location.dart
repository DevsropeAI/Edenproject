import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/network/api_client.dart';
import '../../../auth/providers/auth_provider.dart';
import 'property_map.dart';

class ContractorLocationSharing extends ConsumerStatefulWidget {
  const ContractorLocationSharing({super.key, required this.bookingId});

  final int bookingId;

  @override
  ConsumerState<ContractorLocationSharing> createState() =>
      _ContractorLocationSharingState();
}

class _ContractorLocationSharingState
    extends ConsumerState<ContractorLocationSharing>
    with
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin<ContractorLocationSharing> {
  Timer? _timer;
  Future<void>? _pending;
  late final ApiClient _api;
  bool _sharing = false;
  bool _busy = false;
  bool _paused = false;
  bool _hasSharedLocation = false;
  String? _notice;

  String get _path => '/bookings/${widget.bookingId}/location';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiClientProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _sharing = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A visible web tab can lose focus without being hidden.
    final paused =
        state != AppLifecycleState.resumed &&
        !(kIsWeb && state == AppLifecycleState.inactive);
    if (_paused == paused) return;
    setState(() => _paused = paused);
    if (!paused) _queueUpdate();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _notice = null;
      _hasSharedLocation = false;
    });
    try {
      if (!kIsWeb) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (!mounted) return;
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          setState(() => _notice = 'Enable location access to start sharing.');
          return;
        }
      }
      setState(() => _sharing = true);
      _timer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _queueUpdate(),
      );
      _queueUpdate();
    } catch (_) {
      if (mounted)
        setState(() => _notice = 'Could not start location sharing.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _queueUpdate() {
    if (!_sharing || _paused || _pending != null) return;
    _pending = _sendLocation().whenComplete(() => _pending = null);
  }

  Future<void> _sendLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted || !_sharing || _paused) return;
      await _api.post(
        _path,
        data: {'latitude': position.latitude, 'longitude': position.longitude},
      );
      if (mounted && _sharing) {
        setState(() {
          _hasSharedLocation = true;
          _notice = 'Sharing your location with the customer.';
        });
      }
    } on PermissionDeniedException {
      if (mounted && _sharing) {
        if (!_hasSharedLocation) _timer?.cancel();
        setState(() {
          _sharing = _hasSharedLocation;
          _notice = _hasSharedLocation
              ? 'Location access is temporarily unavailable. Check browser permission. Eden will retry.'
              : 'Location permission was denied. Allow location access and try again.';
        });
      }
    } catch (_) {
      if (mounted && _sharing)
        setState(() => _notice = 'Location update failed. Retrying…');
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final path = _path;
    setState(() {
      _sharing = false;
      _busy = true;
      _notice = null;
    });
    try {
      await _pending;
      if (mounted) await _api.delete(path);
    } catch (_) {
      if (mounted)
        setState(() => _notice = 'Your last location will expire shortly.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : (_sharing ? _stop : _start),
          icon: const Icon(Icons.my_location),
          label: Text(
            _sharing ? 'Stop sharing location' : 'Share live location',
          ),
        ),
        Text(
          (_sharing && _paused
                  ? 'Location sharing is paused. Return to this screen to resume.'
                  : _notice) ??
              (_sharing
                  ? 'Getting your location…'
                  : 'Keep this screen open to share your location.'),
        ),
      ],
    );
  }
}

class CustomerTrackingMap extends ConsumerStatefulWidget {
  const CustomerTrackingMap({
    super.key,
    required this.bookingId,
    this.propertyPin,
  });
  final int bookingId;
  final LatLng? propertyPin;

  @override
  ConsumerState<CustomerTrackingMap> createState() =>
      _CustomerTrackingMapState();
}

class _CustomerTrackingMapState extends ConsumerState<CustomerTrackingMap> {
  Timer? _timer;
  LatLng? _location;
  bool _loading = false;
  bool _failed = false;
  bool _hasReceivedLocation = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    final id = widget.bookingId;
    try {
      final account = ref.read(activeAccountIdProvider);
      final result = await ref
          .read(apiClientProvider)
          .get('/bookings/$id/location');
      if (!mounted || account != ref.read(activeAccountIdProvider)) return;
      final value = result.data['location'] as Map?;
      setState(() {
        _failed = false;
        _location = value == null
            ? null
            : LatLng(
                (value['latitude'] as num).toDouble(),
                (value['longitude'] as num).toDouble(),
              );
        if (_location != null) _hasReceivedLocation = true;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _location = null;
          _failed = true;
        });
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = _location;
    final mapCenter = location ?? widget.propertyPin;
    final status = switch ((location != null, _failed, _hasReceivedLocation)) {
      (true, _, _) => 'Live contractor location',
      (_, true, _) => 'Could not load live location. Retrying…',
      (_, _, true) => 'Live location paused. Waiting for a fresh update.',
      _ => 'Waiting for the contractor to share their location.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(status),
        if (mapCenter != null) ...[
          const SizedBox(height: 8),
          if (location == null) const Text('Map shows the service property.'),
          PropertyMap(initial: mapCenter),
        ],
      ],
    );
  }
}
