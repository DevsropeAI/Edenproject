import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class PropertyMap extends StatefulWidget {
  const PropertyMap({
    super.key,
    required this.initial,
    this.editable = false,
    this.locateOnOpen = false,
  });
  final LatLng initial;
  final bool editable;
  final bool locateOnOpen;

  @override
  State<PropertyMap> createState() => _PropertyMapState();
}

class _PropertyMapState extends State<PropertyMap> {
  late LatLng _pin = widget.initial;
  final _controller = MapController();
  bool _ready = false;
  late bool _hasPin = !widget.locateOnOpen;
  bool _locating = false;
  int _selection = 0;
  String? _locationError;

  Future<void> _locate() async {
    if (_locating) return;
    final selection = _selection;
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      if (!kIsWeb &&
          await Geolocator.checkPermission() == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      if (!mounted || selection != _selection) return;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted || selection != _selection) return;
      setState(() {
        _pin = LatLng(position.latitude, position.longitude);
        _hasPin = true;
      });
      if (_ready) _controller.move(_pin, 16);
    } catch (_) {
      if (mounted && selection == _selection) {
        setState(() {
          _locationError = 'Could not get your location. Check location permission or tap the map to place a pin.';
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  void didUpdateWidget(covariant PropertyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.editable && oldWidget.initial != widget.initial) {
      _pin = widget.initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ready) _controller.move(_pin, _controller.camera.zoom);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 280,
        child: FlutterMap(
          mapController: _controller,
          options: MapOptions(
            onMapReady: () {
              _ready = true;
              if (widget.locateOnOpen) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_hasPin) _locate();
                });
              }
            },
            initialCenter: _pin,
            initialZoom: 14,
            maxZoom: 19,
            onTap: widget.editable
                ? (_, point) => setState(() {
                    _selection++;
                    _pin = point;
                    _hasPin = true;
                    _locationError = null;
                  })
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.eden_frontend',
            ),
            MarkerLayer(
              markers: [
                if (_hasPin)
                  Marker(
                    point: _pin,
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.location_on,
                      color: Theme.of(context).colorScheme.primary,
                      size: 38,
                    ),
                  ),
              ],
            ),
            const Align(
              alignment: Alignment.bottomRight,
              child: ColoredBox(
                color: Colors.white,
                child: Text(' © OpenStreetMap contributors '),
              ),
            ),
          ],
        ),
      ),
      if (widget.editable) ...[
        const SizedBox(height: 8),
        const Text('Tap the map to move the pin.'),
        if (_locationError case final error?) Text(error),
        OutlinedButton.icon(
          onPressed: _locating ? null : _locate,
          icon: const Icon(Icons.my_location),
          label: Text(
            _locating ? 'Finding your location…' : 'Use my current location',
          ),
        ),
        FilledButton(
          onPressed: _hasPin ? () => Navigator.pop(context, _pin) : null,
          child: const Text('Use this pin'),
        ),
      ],
    ],
  );
}
