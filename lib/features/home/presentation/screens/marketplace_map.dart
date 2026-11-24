import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import 'marketplace_screens.dart';
import 'google_marketplace_canvas.dart';

final marketplaceMapProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) async {
    ref.watch(activeAccountIdProvider);
    final timer = Timer(
      const Duration(seconds: 15),
      () => ref.invalidateSelf(),
    );
    ref.onDispose(timer.cancel);
    final response = await ref.watch(apiClientProvider).get('/contractor/map');
    return Map<String, dynamic>.from(response.data as Map);
  },
);

class MarketplaceMap extends ConsumerStatefulWidget {
  const MarketplaceMap({super.key});
  @override
  ConsumerState<MarketplaceMap> createState() => _MarketplaceMapState();
}

class _MarketplaceMapState extends ConsumerState<MarketplaceMap> {
  final _filters = {
    'customers',
    'contractors',
    'small',
    'large',
    'active',
    'completed',
  };
  static const _labels = {
    'customers': 'Customers',
    'contractors': 'Contractors',
    'small': 'Small leads',
    'large': 'Large leads',
    'active': 'Active jobs',
    'completed': 'Completed',
  };
  void _showLegend(Map config) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: EdenDarkColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(EdenRadius.card),
        ),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            EdenSpacing.section,
            0,
            EdenSpacing.section,
            EdenSpacing.section,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Map key', style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: EdenSpacing.section),
              for (final entry in {
                'customer': 'Small open lead',
                'large': 'Large open lead',
                'contractor': 'Contractor',
                'active': 'Active job',
                'completed': 'Completed job',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: EdenSpacing.screen),
                  child: Row(
                    children: [
                      SizedBox(
                        width: EdenSpacing.target,
                        child: Center(
                          child: _MapSymbol(
                            Map<String, dynamic>.from(config[entry.key] as Map),
                            dimension: EdenSpacing.section,
                          ),
                        ),
                      ),
                      const SizedBox(width: EdenSpacing.sm),
                      Expanded(child: Text(entry.value)),
                    ],
                  ),
                ),
              Text(
                'Solid blue means a live location. Outlined blue means a last shared location or approximate work city.',
                style: Theme.of(sheet).textTheme.bodySmall,
              ),
              const SizedBox(height: EdenSpacing.screen),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> m) {
    showCustomerDialog<void>(
      context: context,
      dark: true,
      builder: (dialog) => PointerInterceptor(
        child: AlertDialog(
          title: Text(m['title'] as String),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m['detail'] as String),
                if (m['details'] case final Map d) ...[
                  if (d['property'] case final Map p) ...[
                    Text(p['name'] as String? ?? ''),
                    Text(p['address'] as String? ?? ''),
                    Text(d['notes'] as String? ?? ''),
                    Text('CAD ${d['total']}'),
                  ] else ...[
                    Text(d['workCity'] as String? ?? ''),
                    Text(d['service'] as String? ?? ''),
                    if (m['locationSource'] == 'work_city')
                      const Text('Approximate work-city location'),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  bool _visible(Map m) => m['kind'] == 'contractor'
      ? _filters.contains('contractors')
      : _filters.contains('customers') &&
            _filters.contains(
              m['kind'] == 'active' || m['kind'] == 'completed'
                  ? m['kind']
                  : m['category'] ?? 'small',
            );
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(marketplaceMapProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Job map',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (data.value case final value?)
              TextButton.icon(
                onPressed: () => _showLegend(value['config'] as Map),
                icon: const Icon(Icons.info_outline, size: EdenSpacing.screen),
                label: const Text('Map key'),
              ),
          ],
        ),
        if (data.isLoading && !data.hasValue) const LinearProgressIndicator(),
        if (data.hasError)
          TextButton(
            onPressed: () => ref.invalidate(marketplaceMapProvider),
            child: const Text('Could not load map. Retry'),
          ),
        if (data.value case final value?) ...[
          Text(
            'Assigned jobs and work locations',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: EdenSpacing.screen),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in _labels.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: EdenSpacing.sm),
                    child: FilterChip(
                      label: Text(entry.value),
                      selected: _filters.contains(entry.key),
                      showCheckmark: false,
                      backgroundColor: EdenDarkColors.glass,
                      selectedColor: EdenDarkColors.strongGlass,
                      labelStyle: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: EdenDarkColors.text),
                      avatar: _filters.contains(entry.key)
                          ? const Icon(
                              Icons.check,
                              size: EdenSpacing.screen,
                              color: EdenDarkColors.accent,
                            )
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(EdenRadius.pill),
                      ),
                      side: BorderSide(
                        color: _filters.contains(entry.key)
                            ? EdenDarkColors.outline
                            : EdenDarkColors.strongGlass,
                      ),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _filters.add(entry.key);
                        } else {
                          _filters.remove(entry.key);
                        }
                      }),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: EdenSpacing.screen),
          Builder(
            builder: (context) {
              final markers = (value['markers'] as List)
                  .map((m) => Map<String, dynamic>.from(m as Map))
                  .where(_visible)
                  .toList();
              if (markers.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(EdenSpacing.screen),
                  child: Text(
                    'No visible locations yet. Accepted jobs with saved pins appear here.',
                  ),
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(EdenRadius.field),
                child: SizedBox(
                  height: 320,
                  child: kIsWeb
                      ? GoogleMarketplaceCanvas(
                          markers: markers,
                          config: Map<String, dynamic>.from(
                            value['config'] as Map,
                          ),
                          onSelected: _showDetails,
                        )
                      : FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(
                              (markers.first['latitude'] as num).toDouble(),
                              (markers.first['longitude'] as num).toDouble(),
                            ),
                            initialZoom: 12,
                            maxZoom: 19,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.eden_frontend',
                            ),
                            MarkerLayer(
                              markers: [
                                for (final m in markers)
                                  Marker(
                                    point: LatLng(
                                      (m['latitude'] as num).toDouble(),
                                      (m['longitude'] as num).toDouble(),
                                    ),
                                    width: 60,
                                    height: 60,
                                    child: IconButton(
                                      tooltip: m['title'] as String,
                                      onPressed: () => _showDetails(m),
                                      icon: Opacity(
                                        opacity: m['online'] == false
                                            ? (value['config']['offlineOpacity']
                                                      as num)
                                                  .toDouble()
                                            : 1,
                                        child: _MapSymbol(
                                          Map<String, dynamic>.from(
                                            value['config'][m['kind']] as Map,
                                          ),
                                          offline: m['online'] == false,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const Align(
                              alignment: Alignment.bottomRight,
                              child: Text('© OpenStreetMap contributors'),
                            ),
                          ],
                        ),
                ),
              );
            },
          ),
          const SizedBox(height: EdenSpacing.gap),
          Text(
            value['notice'] as String,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: EdenDarkColors.secondary),
          ),
        ],
      ],
    );
  }
}

class _MapSymbol extends StatelessWidget {
  const _MapSymbol(this.style, {this.offline = false, this.dimension});
  final Map<String, dynamic> style;
  final bool offline;
  final double? dimension;
  @override
  Widget build(BuildContext context) {
    final color = Color(
      int.parse((style['color'] as String).replaceFirst('#', 'FF'), radix: 16),
    );
    final size = dimension ?? (style['size'] as num).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            style['shape'] == 'circle'
                ? (offline ? Icons.circle_outlined : Icons.circle)
                : Icons.location_on,
            color: color,
            size: size,
          ),
          if (style['badge'] != null)
            Positioned.fill(
              child: Align(
                alignment: const Alignment(0, -0.25),
                child: SizedBox(
                  width: size / 2,
                  height: size / 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: style['badge'] == '◉'
                        ? const Icon(
                            Icons.circle_outlined,
                            color: EdenDarkColors.text,
                          )
                        : style['badge'] == '✓'
                        ? const Icon(Icons.check, color: EdenDarkColors.text)
                        : Text(
                            style['badge'] as String,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: EdenDarkColors.text,
                                  height: 1,
                                ),
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
