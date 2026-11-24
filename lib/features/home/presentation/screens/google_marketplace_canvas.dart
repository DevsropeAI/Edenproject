import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;

import '../../../../core/maps/google_maps_loader.dart';
import '../../../../core/theme/app_colors.dart';

class GoogleMarketplaceCanvas extends StatefulWidget {
  const GoogleMarketplaceCanvas({
    super.key,
    required this.markers,
    required this.config,
    required this.onSelected,
    this.selectedId,
  });
  final List<Map<String, dynamic>> markers;
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final String? selectedId;

  @override
  State<GoogleMarketplaceCanvas> createState() =>
      _GoogleMarketplaceCanvasState();
}

class _GoogleMarketplaceCanvasState extends State<GoogleMarketplaceCanvas> {
  static final _icons = <String, Future<google.BitmapDescriptor>>{};
  late Future<void> _ready = loadGoogleMaps();

  Future<google.BitmapDescriptor> _icon(Map marker) {
    final style = Map<String, dynamic>.from(
      widget.config[marker['kind']] as Map,
    );
    final offline = marker['online'] == false;
    final selected = marker['id'].toString() == widget.selectedId;
    final key = jsonEncode([
      style,
      offline,
      selected,
      widget.config['offlineOpacity'],
    ]);
    return _icons.putIfAbsent(key, () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(2);
      final color = Color(
        int.parse(
          (style['color'] as String).replaceFirst('#', 'FF'),
          radix: 16,
        ),
      );
      final opacity = offline
          ? (widget.config['offlineOpacity'] as num? ?? .45).toDouble()
          : 1.0;
      final paint = Paint()..color = color.withValues(alpha: opacity);
      final radius = (style['size'] as num).toDouble() / 2;
      const center = Offset(30, 25);
      if (selected) {
        canvas.drawCircle(
          center,
          24,
          Paint()
            ..color = EdenDarkColors.text
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      if (style['shape'] == 'circle') {
        if (offline) {
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3;
        }
        canvas.drawCircle(center, radius, paint);
      } else {
        final path = Path()
          ..moveTo(30, 25 + radius + 8)
          ..cubicTo(
            30 - radius * 1.5,
            25,
            30 - radius,
            25 - radius,
            30,
            25 - radius,
          )
          ..cubicTo(
            30 + radius,
            25 - radius,
            30 + radius * 1.5,
            25,
            30,
            25 + radius + 8,
          )
          ..close();
        canvas.drawPath(path, paint);
      }
      if (marker['kind'] == 'active') {
        canvas.drawCircle(
          center,
          6,
          Paint()
            ..color = EdenDarkColors.text
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else if (style['badge'] != null) {
        final text = TextPainter(
          text: TextSpan(
            text: style['badge'] as String,
            style: const TextStyle(
              color: EdenDarkColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(30 - text.width / 2, 25 - text.height / 2));
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(120, 120);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return google.BitmapDescriptor.bytes(
        bytes!.buffer.asUint8List(),
        width: 60,
        height: 60,
        imagePixelRatio: 2,
      );
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, ready) {
      if (ready.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Google Maps could not load. Check the map key and connection.',
              ),
              TextButton(
                onPressed: () => setState(() => _ready = loadGoogleMaps()),
                child: const Text('Retry map'),
              ),
            ],
          ),
        );
      }
      if (ready.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      return _GoogleMarkers(
        markers: widget.markers,
        icons: _icon,
        onSelected: widget.onSelected,
        selectedId: widget.selectedId,
      );
    },
  );
}

class _GoogleMarkers extends StatefulWidget {
  const _GoogleMarkers({
    required this.markers,
    required this.icons,
    required this.onSelected,
    this.selectedId,
  });
  final List<Map<String, dynamic>> markers;
  final Future<google.BitmapDescriptor> Function(Map) icons;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final String? selectedId;
  @override
  State<_GoogleMarkers> createState() => _GoogleMarkersState();
}

class _GoogleMarkersState extends State<_GoogleMarkers> {
  Set<google.Marker> _markers = {};
  int _version = 0;
  google.GoogleMapController? _controller;
  String? _markerError;
  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(covariant _GoogleMarkers oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
    if (oldWidget.selectedId != widget.selectedId ||
        oldWidget.markers.map((marker) => marker['id']).join(',') !=
            widget.markers.map((marker) => marker['id']).join(',')) {
      _focus();
    }
  }

  Future<void> _focus() async {
    final controller = _controller;
    if (controller == null || widget.markers.isEmpty) return;
    final selected = widget.markers
        .where((marker) => marker['id'].toString() == widget.selectedId)
        .firstOrNull;
    if (selected != null) {
      await controller.animateCamera(
        google.CameraUpdate.newLatLngZoom(
          google.LatLng(
            (selected['latitude'] as num).toDouble(),
            (selected['longitude'] as num).toDouble(),
          ),
          16,
        ),
      );
      return;
    }
    if (widget.markers.length == 1) {
      final marker = widget.markers.first;
      await controller.animateCamera(
        google.CameraUpdate.newLatLngZoom(
          google.LatLng(
            (marker['latitude'] as num).toDouble(),
            (marker['longitude'] as num).toDouble(),
          ),
          13,
        ),
      );
      return;
    }
    final latitudes =
        widget.markers
            .map((marker) => (marker['latitude'] as num).toDouble())
            .toList()
          ..sort();
    final longitudes =
        widget.markers
            .map((marker) => (marker['longitude'] as num).toDouble())
            .toList()
          ..sort();
    await controller.animateCamera(
      google.CameraUpdate.newLatLngBounds(
        google.LatLngBounds(
          southwest: google.LatLng(latitudes.first, longitudes.first),
          northeast: google.LatLng(latitudes.last, longitudes.last),
        ),
        36,
      ),
    );
  }

  Future<void> _update() async {
    final version = ++_version;
    try {
      final markers = await Future.wait(
        widget.markers.map(
          (marker) async => google.Marker(
            markerId: google.MarkerId(marker['id'].toString()),
            position: google.LatLng(
              (marker['latitude'] as num).toDouble(),
              (marker['longitude'] as num).toDouble(),
            ),
            icon: await widget.icons(marker),
            anchor: const Offset(.5, .5),
            consumeTapEvents: true,
            infoWindow: google.InfoWindow(title: marker['title'] as String?),
            onTap: () => widget.onSelected(marker),
          ),
        ),
      );
      if (mounted && version == _version) {
        setState(() {
          _markers = markers.toSet();
          _markerError = null;
        });
      }
    } catch (_) {
      if (mounted && version == _version) {
        setState(
          () => _markerError =
              'Could not draw job pins. Reopen this page to retry.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => _markerError != null
      ? Center(child: Text(_markerError!))
      : google.GoogleMap(
          initialCameraPosition: google.CameraPosition(
            target: google.LatLng(
              (widget.markers.first['latitude'] as num).toDouble(),
              (widget.markers.first['longitude'] as num).toDouble(),
            ),
            zoom: 12,
          ),
          minMaxZoomPreference: const google.MinMaxZoomPreference(null, 19),
          markers: _markers,
          onMapCreated: (controller) {
            _controller = controller;
            _focus();
          },
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
        );
}
