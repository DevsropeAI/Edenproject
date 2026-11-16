import 'dart:async';

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
    with WidgetsBindingObserver {
  Timer? _timer;
  Future<void>? _pending;
  late final ApiClient _api;
  bool _sharing = false;
  bool _busy = false;
  String? _notice;

  String get _path => '/bookings/${widget.bookingId}/location';

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
    if (state != AppLifecycleState.resumed && _sharing) unawaited(_stop());
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (!mounted) return;
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        setState(() => _notice = 'Enable location access to start sharing.');
        return;
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
    if (!_sharing || _pending != null) return;
    _pending = _sendLocation().whenComplete(() => _pending = null);
  }

  Future<void> _sendLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted || !_sharing) return;
      await _api.post(
        _path,
        data: {'latitude': position.latitude, 'longitude': position.longitude},
      );
      if (mounted && _sharing)
        setState(() => _notice = 'Sharing your location with the customer.');
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        onPressed: _busy ? null : (_sharing ? _stop : _start),
        icon: const Icon(Icons.my_location),
        label: Text(_sharing ? 'Stop sharing location' : 'Share live location'),
      ),
      Text(
        _notice ??
            (_sharing
                ? 'Getting your location…'
                : 'Keep this screen open to share your location.'),
      ),
    ],
  );
}

class CustomerTrackingMap extends ConsumerStatefulWidget {
  const CustomerTrackingMap({super.key, required this.bookingId});
  final int bookingId;

  @override
  ConsumerState<CustomerTrackingMap> createState() =>
      _CustomerTrackingMapState();
}

class _CustomerTrackingMapState extends ConsumerState<CustomerTrackingMap> {
  Timer? _timer;
  LatLng? _location;
  bool _loading = false;

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
      setState(
        () => _location = value == null
            ? null
            : LatLng(
                (value['latitude'] as num).toDouble(),
                (value['longitude'] as num).toDouble(),
              ),
      );
    } catch (_) {
      if (mounted) setState(() => _location = null);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = _location;
    if (location == null)
      return const Text('Waiting for the contractor to share their location.');
    return PropertyMap(initial: location);
  }
}
