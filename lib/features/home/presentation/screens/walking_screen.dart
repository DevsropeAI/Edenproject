import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/network/api_client.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import 'marketplace_screens.dart';
import 'walking_wake.dart';

final walkingStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  ref.watch(activeAccountIdProvider);
  final timer = Timer(const Duration(seconds: 15), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final r = await ref.watch(apiClientProvider).get('/walking/status');
  return Map<String, dynamic>.from(r.data as Map);
});

class WalkingScreen extends ConsumerStatefulWidget {
  const WalkingScreen({super.key});
  @override
  ConsumerState<WalkingScreen> createState() => _WalkingScreenState();
}

class _WalkingScreenState extends ConsumerState<WalkingScreen>
    with WidgetsBindingObserver {
  final _queue = <Map<String, dynamic>>[];
  Map<String, dynamic>? _shift;
  StreamSubscription<Position>? _positions;
  Timer? _sampleTimer, _flushTimer, _clock;
  bool _recording = false,
      _hidden = false,
      _busy = false,
      _uploading = false,
      _locating = false,
      _gap = true,
      _stopping = false;
  bool _wake = false;
  int _sequence = 0;
  double _distance = 0;
  Position? _last;
  DateTime? _lastReceived;
  String? _error;
  late final ApiClient _api;
  int _accuracy = 50, _gapSeconds = 45;

  @override
  void initState() {
    super.initState();
    _api = ref.read(apiClientProvider);
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _halt();
    _clock?.cancel();
    releaseWalkingWakeLock();
    super.dispose();
  }

  void _halt() {
    _recording = false;
    _positions?.cancel();
    _positions = null;
    _sampleTimer?.cancel();
    _flushTimer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final hidden =
        state != AppLifecycleState.resumed &&
        !(kIsWeb && state == AppLifecycleState.inactive);
    if (hidden == _hidden) return;
    _hidden = hidden;
    _gap = true;
    _last = null;
    if (!hidden && _recording) {
      requestWalkingWakeLock().then((v) {
        if (mounted) setState(() => _wake = v);
      });
      _sample();
    }
    if (mounted) setState(() {});
  }

  Future<void> _sample() async {
    if (!_recording || _hidden || _locating) return;
    _locating = true;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _point(p);
    } catch (_) {
      _gap = true;
      if (mounted) {
        setState(
          () => _error = 'Location unavailable. Recording will resume when a fresh position is available.',
        );
      }
    } finally {
      _locating = false;
    }
  }

  void _point(Position p) {
    if (!mounted ||
        !_recording ||
        _hidden ||
        p.accuracy > _accuracy ||
        p.accuracy < 0 ||
        !p.latitude.isFinite ||
        !p.longitude.isFinite) {
      return;
    }
    final now = DateTime.now();
    final start = DateTime.parse(_shift!['startedAt'] as String);
    if (p.timestamp.isBefore(start) ||
        now.difference(p.timestamp).inSeconds > 20) {
      return;
    }
    if (_queue.isNotEmpty &&
        DateTime.parse(_queue.last['recordedAt'] as String)
                .compareTo(p.timestamp) >=
            0) {
      return;
    }
    if (_last != null && p.timestamp.compareTo(_last!.timestamp) <= 0) return;
    final moved = _last == null
        ? 0.0
        : Geolocator.distanceBetween(
            _last!.latitude,
            _last!.longitude,
            p.latitude,
            p.longitude,
          );
    final elapsed = _lastReceived == null
        ? 999
        : now.difference(_lastReceived!).inSeconds;
    if (!_gap && elapsed < 12 && moved < 15) return;
    final gap = _gap || elapsed > _gapSeconds || _last == null;
    _queue.add({
      'sequence': ++_sequence,
      'latitude': p.latitude,
      'longitude': p.longitude,
      'accuracyM': p.accuracy,
      'recordedAt': p.timestamp.toUtc().toIso8601String(),
      'gapBefore': gap,
    });
    _last = p;
    _lastReceived = now;
    _gap = false;
    setState(() => _error = null);
    if (_queue.length >= 5) _flush();
  }

  Future<void> _flush() async {
    if (_uploading || _queue.isEmpty || _shift == null) return;
    _uploading = true;
    final batch = _queue.take(100).toList();
    try {
      final r = await _api.post(
        '/walking/shifts/${_shift!['id']}/points',
        data: {'points': batch},
      );
      _queue.removeRange(0, batch.length);
      _distance = (r.data['distanceM'] as num).toDouble();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              '${apiError(e)} Unsent points remain in memory; Eden will retry.',
        );
      }
    } finally {
      _uploading = false;
    }
  }

  Future<void> _begin(Map<String, dynamic> status) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw StateError('Enable browser location permission to start.');
      }
      if (_shift == null) {
        if (status['shift'] != null) {
          _shift = Map<String, dynamic>.from(status['shift'] as Map);
        } else {
          final r = await _api.post('/walking/shifts/start', data: {});
          _shift = Map<String, dynamic>.from(r.data['shift'] as Map);
        }
        _sequence = (_shift!['lastSequence'] as num?)?.toInt() ?? 0;
        _distance = double.tryParse('${_shift!['distanceM']}') ?? 0;
      }
      if (!mounted) return;
      _accuracy = (status['config']['accuracyM'] as num).toInt();
      _gapSeconds = (status['config']['gapSeconds'] as num).toInt();
      _recording = true;
      _gap = true;
      _last = null;
      _wake = await requestWalkingWakeLock();
      if (!mounted) {
        _halt();
        await releaseWalkingWakeLock();
        return;
      }
      _positions =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 15,
            ),
          ).listen(
            _point,
            onError: (_) {
              _gap = true;
            },
          );
      _sampleTimer = Timer.periodic(
        const Duration(seconds: 12),
        (_) => _sample(),
      );
      _flushTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        await _flush();
      });
      _sample();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StateError ? e.message : apiError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    _halt();
    await releaseWalkingWakeLock();
    setState(() {
      _busy = true;
      _stopping = true;
    });
    try {
      while (_uploading) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      while (_queue.isNotEmpty) {
        final count = _queue.length;
        await _flush();
        if (_queue.length == count) {
          throw StateError(
            'Recording stopped. Retry Stop shift to upload pending points and finish.',
          );
        }
      }
      await _api.post('/walking/shifts/${_shift!['id']}/stop', data: {});
      if (mounted) {
        setState(() {
          _shift = null;
          _stopping = false;
          _error = null;
        });
      }
      ref.invalidate(walkingStatusProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StateError ? e.message : apiError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(walkingStatusProvider);
    final status = state.value;
    ref.listen(walkingStatusProvider, (previous, next) {
      if (next.isLoading || next.hasError) return;
      final v = next.value;
      if (v == null || !_recording) return;
      if (v['enabled'] != true || v['shift'] == null) {
        _halt();
        releaseWalkingWakeLock();
        if (mounted) {
          setState(() {
            _queue.clear();
            _shift = null;
            _stopping = false;
            _error = 'Tracking stopped: the shift ended or access was disabled. Unsent points were discarded.';
          });
        }
      }
    });
    final paused =
        _hidden ||
        _lastReceived == null ||
        DateTime.now().difference(_lastReceived!).inSeconds > _gapSeconds;
    final duration = _shift == null
        ? Duration.zero
        : DateTime.now().difference(
            DateTime.parse(_shift!['startedAt'] as String),
          );
    return PopScope(
      canPop: !_recording && !_stopping,
      child: MarketPage(
        dark: true,
        title: 'Door-to-door',
        children: [
          const MarketBanner(
            'Walking shifts',
            'GPS is recorded only during a shift and routes are visible only to admins.',
            Icons.directions_walk,
          ),
          if (state.isLoading && status == null)
            const LinearProgressIndicator(),
          if (state.hasError)
            TextButton(
              onPressed: () => ref.invalidate(walkingStatusProvider),
              child: const Text('Could not load walking access. Retry'),
            ),
          if (status != null && status['enabled'] != true)
            const Text('Door-to-door access is not enabled for this account.'),
          if (status != null && status['enabled'] == true) ...[
            if (status['consented'] != true) ...[
              MarketCard(
                solid: true,
                children: [
                  Text(
                    'Location consent',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (status['policy']?['isPlaceholder'] == 1 ||
                      status['policy']?['isPlaceholder'] == true)
                    const Text('Placeholder wording — pending approval'),
                  Text(
                    status['policy']?['body'] as String? ??
                        'Consent wording is not configured.',
                  ),
                  Text(
                    'Route retention: up to ${status['config']['retentionDays']} days after the shift ends.',
                  ),
                  FilledButton(
                    onPressed: _busy || status['policy'] == null
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            try {
                              await _api.post(
                                '/walking/consent',
                                data: {'version': status['policy']['version']},
                              );
                              ref.invalidate(walkingStatusProvider);
                            } catch (e) {
                              if (mounted) setState(() => _error = apiError(e));
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                    child: const Text('I agree'),
                  ),
                ],
              ),
            ] else
              MarketCard(
                children: [
                  Text(
                    _recording
                        ? (paused ? 'Tracking paused' : 'Tracking is on')
                        : _stopping
                        ? 'Recording stopped · upload pending'
                        : 'Ready to walk',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_shift != null)
                    Text(
                      '${duration.inHours}h ${duration.inMinutes.remainder(60)}m · ${(_distance / 1000).toStringAsFixed(2)} km uploaded',
                    ),
                  Text('${_queue.length} points waiting to upload'),
                  const Text(
                    'Keep this page open and visible. Browser minimising, screen lock or closing the app can pause recording. Closing loses unsent points.',
                  ),
                  if (_recording)
                    Text(
                      _wake
                          ? 'Screen wake lock requested. Keep checking that the screen stays on.'
                          : 'Screen wake lock unavailable. Keep the screen awake manually.',
                    ),
                  if (!_recording && !_stopping)
                    FilledButton(
                      onPressed: _busy ? null : () => _begin(status),
                      child: Text(
                        status['shift'] == null
                            ? 'Start shift'
                            : 'Resume active shift',
                      ),
                    ),
                  if (_shift != null || status['shift'] != null)
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () {
                              _shift ??= Map<String, dynamic>.from(
                                status['shift'] as Map,
                              );
                              _stop();
                            },
                      child: Text(
                        _stopping ? 'Retry upload and stop' : 'Stop shift',
                      ),
                    ),
                  if (_recording)
                    const Text('Stop the shift before leaving this screen.'),
                ],
              ),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
        ],
      ),
    );
  }
}

class WalkingEntry extends ConsumerWidget {
  const WalkingEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(walkingStatusProvider);
    if (status.value?['enabled'] != true) return const SizedBox.shrink();
    return OutlinedButton.icon(
      icon: const Icon(Icons.directions_walk),
      label: const Text('Door-to-door walking'),
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const WalkingScreen())),
    );
  }
}
