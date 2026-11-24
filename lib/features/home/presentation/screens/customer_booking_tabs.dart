import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/glass_controls.dart';
import '../../marketplace.dart';
import 'marketplace_screens.dart' show BookingMessageButton, bookingDateLabel;
import 'customer_booking_update_reader.dart';

enum CustomerBookingTab { newBookings, inProgress, completed, past }

List<Booking> customerTabBookings(
  List<Booking> bookings,
  CustomerBookingTab tab,
) => bookings
    .where(
      (booking) => switch (tab) {
        CustomerBookingTab.newBookings => booking.status == JobStatus.searching,
        CustomerBookingTab.inProgress => ![
          JobStatus.searching,
          JobStatus.completed,
          JobStatus.cancelled,
        ].contains(booking.status),
        CustomerBookingTab.completed => booking.status == JobStatus.completed,
        CustomerBookingTab.past => [
          JobStatus.completed,
          JobStatus.cancelled,
        ].contains(booking.status),
      },
    )
    .toList();

class CustomerBookingTabs extends StatefulWidget {
  const CustomerBookingTabs({
    super.key,
    required this.bookings,
    required this.onOpen,
    required this.onRefresh,
    this.onBrowse,
    this.heading = 'Your bookings',
  });
  final List<Booking> bookings;
  final ValueChanged<Booking> onOpen;
  final Future<void> Function() onRefresh;
  final VoidCallback? onBrowse;
  final String heading;

  @override
  State<CustomerBookingTabs> createState() => _CustomerBookingTabsState();
}

class _CustomerBookingTabsState extends State<CustomerBookingTabs> {
  late CustomerBookingTab _tab = _recommendedTab();
  bool _chosen = false;
  bool _refreshing = false;
  String? _error;

  CustomerBookingTab _recommendedTab() => CustomerBookingTab.values.firstWhere(
    (tab) => customerTabBookings(widget.bookings, tab).isNotEmpty,
    orElse: () => CustomerBookingTab.newBookings,
  );

  @override
  void didUpdateWidget(covariant CustomerBookingTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_chosen) _tab = _recommendedTab();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await widget.onRefresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not refresh bookings. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = customerTabBookings(widget.bookings, _tab);
    final text = Theme.of(context).textTheme;
    final money = NumberFormat.simpleCurrency(name: 'CAD');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.heading, style: text.titleLarge)),
            IconButton(
              onPressed: _refreshing ? null : _refresh,
              tooltip: 'Refresh bookings',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: EdenSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final tab in CustomerBookingTab.values)
                Padding(
                  padding: const EdgeInsets.only(right: EdenSpacing.sm),
                  child: ChoiceChip(
                    key: ValueKey('customer-tab-${tab.name}'),
                    label: Text(
                      '${switch (tab) {
                        CustomerBookingTab.newBookings => 'New',
                        CustomerBookingTab.inProgress => 'In progress',
                        CustomerBookingTab.completed => 'Completed',
                        CustomerBookingTab.past => 'Past',
                      }} (${customerTabBookings(widget.bookings, tab).length})',
                    ),
                    selected: _tab == tab,
                    avatar:
                        customerTabBookings(
                          widget.bookings,
                          tab,
                        ).any((booking) => booking.hasUnreadUpdates)
                        ? CustomerBookingUpdateBadge(
                            key: ValueKey('customer-tab-update-${tab.name}'),
                            label:
                                'New updates in ${tab.name == 'inProgress'
                                    ? 'in progress'
                                    : tab == CustomerBookingTab.newBookings
                                    ? 'new bookings'
                                    : tab.name}',
                          )
                        : null,
                    onSelected: (_) => setState(() {
                      _tab = tab;
                      _chosen = true;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: EdenSpacing.gap),
        Text(switch (_tab) {
          CustomerBookingTab.newBookings =>
            'Placed bookings waiting for contractor acceptance.',
          CustomerBookingTab.inProgress =>
            'Accepted, on the way, working or awaiting your approval.',
          CustomerBookingTab.completed => 'Services that have been completed.',
          CustomerBookingTab.past =>
            'Your completed and cancelled booking history.',
        }, style: text.bodySmall),
        const SizedBox(height: EdenSpacing.screen),
        if (_refreshing) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (jobs.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            message: switch (_tab) {
              CustomerBookingTab.newBookings =>
                'No bookings waiting for a contractor.',
              CustomerBookingTab.inProgress =>
                'No services in progress right now.',
              CustomerBookingTab.completed =>
                'Your completed services will appear here.',
              CustomerBookingTab.past =>
                'Your completed and cancelled bookings will appear here.',
            },
            action: widget.onBrowse != null
                ? TextButton(
                    onPressed: widget.onBrowse,
                    child: const Text('Browse services'),
                  )
                : TextButton(
                    onPressed: _refreshing ? null : _refresh,
                    child: const Text('Refresh bookings'),
                  ),
          ),
        for (final booking in jobs)
          Padding(
            padding: const EdgeInsets.only(bottom: EdenSpacing.gap),
            child: GlassCard(
              key: ValueKey('customer-booking-${booking.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          booking.service.label,
                          style: text.titleMedium,
                        ),
                      ),
                      if (booking.hasUnreadUpdates) ...[
                        const SizedBox(width: EdenSpacing.sm),
                        CustomerBookingUpdateBadge(
                          key: ValueKey(
                            'customer-booking-update-${booking.id}',
                          ),
                          label:
                              'New update for ${booking.service.label}, booking ${booking.id}',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: EdenSpacing.sm),
                  Text(booking.property.fullAddress),
                  const SizedBox(height: EdenSpacing.sm),
                  Text(
                    '${bookingDateLabel(booking)} · ${money.format(booking.total)} CAD',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: EdenSpacing.gap),
                  StatusChip(
                    label: booking.status.label,
                    status: switch (booking.status) {
                      JobStatus.searching => EdenStatus.pending,
                      JobStatus.completed => EdenStatus.complete,
                      JobStatus.enRoute || JobStatus.working => EdenStatus.live,
                      _ => EdenStatus.neutral,
                    },
                  ),
                  const SizedBox(height: EdenSpacing.sm),
                  Wrap(
                    spacing: EdenSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => widget.onOpen(booking),
                        child: const Text('View details'),
                      ),
                      if (![
                        JobStatus.searching,
                        JobStatus.cancelled,
                      ].contains(booking.status))
                        BookingMessageButton(
                          booking: booking,
                          contractor: false,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
