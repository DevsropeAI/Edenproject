import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class PropertyMap extends StatefulWidget {
  const PropertyMap({super.key, required this.initial, this.editable = false});
  final LatLng initial;
  final bool editable;

  @override
  State<PropertyMap> createState() => _PropertyMapState();
}

class _PropertyMapState extends State<PropertyMap> {
  late LatLng _pin = widget.initial;
  final _controller = MapController();
  bool _ready = false;

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
            onMapReady: () => _ready = true,
            initialCenter: _pin,
            initialZoom: 14,
            maxZoom: 19,
            onTap: widget.editable
                ? (_, point) => setState(() => _pin = point)
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.eden_frontend',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _pin,
                  width: 44,
                  height: 44,
                  child: const Icon(
                    Icons.location_on,
                    color: Color(0xFF164D36),
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
        FilledButton(
          onPressed: () => Navigator.pop(context, _pin),
          child: const Text('Use this pin'),
        ),
      ],
    ],
  );
}
