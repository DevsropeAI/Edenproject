import '../../../../core/widgets/desktop_workspace.dart';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/glass_controls.dart';
import '../../marketplace.dart';
import 'google_marketplace_canvas.dart';
import 'marketplace_screens.dart'
    show bookingDateLabel, BookingMessageButton, JobRequirements;

enum ContractorJobTab { available, active, completed, cancelled }

List<Booking> contractorTabJobs(
  List<Booking> jobs,
  ContractorJobTab tab,
  bool available,
) => jobs.where((job) {
  if (job.declined) return false;
  return switch (tab) {
    ContractorJobTab.available =>
      job.status == JobStatus.searching &&
          job.dispatchStatus != 'rejected' &&
          (job.bookingType != 'long_term' ||
              job.dispatchStatus == 'assigned') &&
          (available || job.dispatchStatus == 'assigned'),
    ContractorJobTab.active => ![
      JobStatus.searching,
      JobStatus.completed,
      JobStatus.cancelled,
    ].contains(job.status),
    ContractorJobTab.completed => job.status == JobStatus.completed,
    ContractorJobTab.cancelled => job.status == JobStatus.cancelled,
  };
}).toList();

List<Map<String, dynamic>> contractorJobMarkers(
  List<Booking> jobs, {
  ({double latitude, double longitude})? position,
}) => [
  if (position != null)
    {
      'id': 'self',
      'kind': 'contractor',
      'title': 'Your location',
      'online': true,
      'latitude': position.latitude,
      'longitude': position.longitude,
    },
  for (final job in jobs.where((job) => job.property.pin != null))
    {
      'id': 'job-${job.id}',
      'bookingId': job.id,
      'kind': job.status == JobStatus.completed
          ? 'completed'
          : job.status == JobStatus.searching
          ? 'customer'
          : 'active',
      'title': job.service.label,
      'detail': job.property.fullAddress,
      'latitude': job.property.pin!.latitude,
      'longitude': job.property.pin!.longitude,
    },
];

typedef ContractorMapBuilder = Widget Function(
  List<Booking> jobs,
  int? selectedId,
  ValueChanged<int> onSelected,
);

class ContractorJobsBrowser extends StatefulWidget {
  const ContractorJobsBrowser({
    super.key,
    required this.jobs,
    required this.available,
    required this.onAvailabilityChanged,
    required this.onRefresh,
    required this.onOpen,
    this.mapBuilder,
  });
  final List<Booking> jobs;
  final bool available;
  final ValueChanged<bool> onAvailabilityChanged;
  final VoidCallback onRefresh;
  final ValueChanged<Booking> onOpen;
  final ContractorMapBuilder? mapBuilder;

  @override
  State<ContractorJobsBrowser> createState() => _ContractorJobsBrowserState();
}

class _ContractorJobsBrowserState extends State<ContractorJobsBrowser> {
  ContractorJobTab _tab = ContractorJobTab.available;
  int? _selectedId;
  bool _showAllPins = true;
  int _cameraRevision = 0;
  final _scroll = ScrollController();
  double _cardExtent = 300;
  Position? _position;
  bool _locating = false;
  String? _locationMessage;
  @override
  void initState() {
    super.initState();
    if (widget.mapBuilder == null) _locate(overview: true);
  }

  Future<void> _locate({bool overview = false}) async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _locationMessage = null;
      _showAllPins = overview;
      _selectedId = null;
      _cameraRevision++;
    });
    try {
      if (!kIsWeb) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied)
          permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever)
          throw StateError('permission');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) setState(() => _position = position);
    } catch (_) {
      if (mounted)
        setState(
          () => _locationMessage = 'Your location is unavailable. Allow location access, then retry. You can still explore the map and jobs.',
        );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  late Future<Map<String, dynamic>> _config = _loadConfig();
  Future<Map<String, dynamic>> _loadConfig() async => Map<String, dynamic>.from(
    jsonDecode(await rootBundle.loadString('shared/map_markers.json')) as Map,
  );
  List<Booking> get _jobs {
    final jobs = contractorTabJobs(widget.jobs, _tab, widget.available);
    if (_position != null && _tab == ContractorJobTab.available) {
      double distance(Booking job) => job.property.pin == null
          ? double.infinity
          : Geolocator.distanceBetween(
              _position!.latitude,
              _position!.longitude,
              job.property.pin!.latitude,
              job.property.pin!.longitude,
            );
      jobs.sort((a, b) {
        final order = distance(a).compareTo(distance(b));
        return order == 0 ? b.id.compareTo(a.id) : order;
      });
    }
    return jobs;
  }

  Booking? get _selected =>
      _jobs.where((job) => job.id == _selectedId).firstOrNull;

  void _select(int id, {bool scroll = false}) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return;
    setState(() {
      _selectedId = id;
      _showAllPins = false;
    });
    if (scroll && _scroll.hasClients) {
      _scroll.animateTo(
        (index * _cardExtent).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void didUpdateWidget(covariant ContractorJobsBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedId != null && _selected == null) _selectedId = null;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _map(List<Booking> jobs) {
    final pinned = jobs.where((job) => job.property.pin != null).toList();
    if (widget.mapBuilder != null) {
      return widget.mapBuilder!(
        pinned,
        _selectedId,
        (id) => _select(id, scroll: true),
      );
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: _config,
      builder: (context, config) {
        if (config.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _config = _loadConfig()),
              child: const Text('Could not load map settings. Retry'),
            ),
          );
        }
        if (!config.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return GoogleMarketplaceCanvas(
          key: ValueKey(_position?.timestamp),
          config: config.requireData,
          initialLocation: _position == null
              ? null
              : (
                  latitude: _position!.latitude,
                  longitude: _position!.longitude,
                ),
          selectedId: _selectedId == null ? null : 'job-$_selectedId',
          fitAllMarkers: _showAllPins,
          cameraRevision: _cameraRevision,
          markers: contractorJobMarkers(
            pinned,
            position: _position == null
                ? null
                : (
                    latitude: _position!.latitude,
                    longitude: _position!.longitude,
                  ),
          ),
          onSelected: (marker) {
            if (marker['bookingId'] case final int id)
              _select(id, scroll: true);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    final selected = _selected;
    final text = Theme.of(context).textTheme;
    final money = NumberFormat.simpleCurrency(name: 'CAD');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Find your next job', style: text.titleLarge),
                  Text(
                    widget.available
                        ? 'One-time jobs · all cities and services'
                        : 'Offline · assigned jobs stay visible',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            Switch(
              value: widget.available,
              onChanged: widget.onAvailabilityChanged,
            ),
            IconButton(
              onPressed: widget.onRefresh,
              tooltip: 'Refresh jobs',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: EdenSpacing.screen),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final tab in ContractorJobTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: EdenSpacing.sm),
                  child: ChoiceChip(
                    label: Text(
                      '${switch (tab) {
                        ContractorJobTab.available => 'Available',
                        ContractorJobTab.active => 'Active',
                        ContractorJobTab.completed => 'Completed',
                        ContractorJobTab.cancelled => 'Cancelled',
                      }} (${contractorTabJobs(widget.jobs, tab, widget.available).length})',
                    ),
                    selected: _tab == tab,
                    onSelected: (_) => setState(() {
                      _tab = tab;
                      _showAllPins = true;
                      _selectedId = null;
                      if (_scroll.hasClients) _scroll.jumpTo(0);
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: EdenSpacing.screen),
        if (EdenDesktopLayout.enabled(context))
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _mapPanel(jobs, selected, text)),
              const SizedBox(width: EdenSpacing.section),
              Expanded(
                flex: 2,
                child: _cardsPanel(jobs, selected, text, money),
              ),
            ],
          )
        else ...[
          _mapPanel(jobs, selected, text),
          _cardsPanel(jobs, selected, text, money),
        ],
        if (selected != null) ...[
          const SizedBox(height: EdenSpacing.screen),
          PointerInterceptor(
            child: InkWell(
              key: const Key('selected-job-description'),
              onTap: () => widget.onOpen(selected),
              borderRadius: BorderRadius.circular(EdenRadius.card),
              child: GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selected.service.label, style: text.titleLarge),
                    const SizedBox(height: EdenSpacing.sm),
                    if (selected.customerName case final name?)
                      Text('Customer: $name'),
                    Text(selected.property.fullAddress),
                    const SizedBox(height: EdenSpacing.sm),
                    Text(selected.status.label, style: text.bodySmall),
                    const SizedBox(height: EdenSpacing.screen),
                    JobRequirements(selected),
                    if (selected.status != JobStatus.searching)
                      BookingMessageButton(booking: selected, contractor: true),
                    const SizedBox(height: EdenSpacing.gap),
                    FilledButton.icon(
                      onPressed: () => widget.onOpen(selected),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('View job details'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _mapPanel(List<Booking> jobs, Booking? selected, TextTheme text) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _locating
                      ? 'Finding your location…'
                      : _locationMessage ??
                            'Your blue marker shows your current location.',
                  style: text.bodySmall,
                ),
              ),
              IconButton(
                onPressed: _locating ? null : () => _locate(),
                tooltip: 'Use my current location',
                icon: const Icon(Icons.my_location),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(EdenRadius.card),
            child: AnimatedContainer(
              key: const Key('contractor-jobs-map'),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              height: EdenDesktopLayout.enabled(context)
                  ? (selected == null ? 430 : 500)
                  : selected == null
                  ? 300
                  : 380,
              color: EdenDarkColors.surface,
              child: _map(jobs),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: EdenSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Blue: you · Red: job locations',
                    style: text.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: jobs.any((job) => job.property.pin != null)
                      ? () => setState(() {
                          _selectedId = null;
                          _showAllPins = true;
                          _cameraRevision++;
                        })
                      : null,
                  child: const Text('Show job pins'),
                ),
              ],
            ),
          ),
        ],
      );
  Widget _cardsPanel(
    List<Booking> jobs,
    Booking? selected,
    TextTheme text,
    NumberFormat money,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (jobs.isEmpty)
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.work_outline),
              const SizedBox(height: EdenSpacing.gap),
              Text(
                _tab == ContractorJobTab.available && !widget.available
                    ? 'Turn on availability to see matching offers.'
                    : 'No ${_tab.name} jobs yet.',
              ),
              TextButton(
                onPressed: widget.onRefresh,
                child: const Text('Refresh jobs'),
              ),
            ],
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final desktop = EdenDesktopLayout.enabled(context);
            final width = desktop
                ? constraints.maxWidth
                : (constraints.maxWidth * .88).clamp(220.0, 360.0);
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final cardHeight = 240 + (scale - 1).clamp(0.0, 2.0) * 180;
            _cardExtent = desktop
                ? cardHeight + EdenSpacing.gap
                : width + EdenSpacing.gap;
            return SizedBox(
              height: desktop ? (selected == null ? 530 : 600) : cardHeight,
              child: ListView.separated(
                controller: _scroll,
                scrollDirection: desktop ? Axis.vertical : Axis.horizontal,
                itemCount: jobs.length,
                separatorBuilder: (_, index) => const SizedBox(
                  width: EdenSpacing.gap,
                  height: EdenSpacing.gap,
                ),
                itemBuilder: (context, index) {
                  final job = jobs[index];
                  final highlighted = selected?.id == job.id;
                  return SizedBox(
                    width: width,
                    height: desktop ? cardHeight : null,
                    child: Semantics(
                      key: Key('job-card-${job.id}'),
                      button: true,
                      selected: highlighted,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(EdenRadius.card),
                          border: Border.all(
                            color: highlighted
                                ? EdenDarkColors.accent
                                : EdenDarkColors.outline,
                            width: highlighted ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(EdenRadius.card),
                          onTap: () => _select(job.id),
                          child: GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        job.service.label,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.titleMedium,
                                      ),
                                    ),
                                    if (job.hasUnreadMessages(true))
                                      const Tooltip(
                                        message: 'Unread messages',
                                        child: Icon(
                                          Icons.mark_chat_unread_outlined,
                                          color: EdenDarkColors.accent,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: EdenSpacing.gap),
                                Text(
                                  job.property.fullAddress,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: EdenSpacing.sm),
                                Text(
                                  bookingDateLabel(job),
                                  style: text.bodySmall,
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${money.format(job.total)} CAD',
                                        style: text.titleMedium,
                                      ),
                                    ),
                                    Icon(
                                      highlighted
                                          ? Icons.check_circle
                                          : Icons.arrow_forward,
                                      color: EdenDarkColors.accent,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
    ],
  );
}
