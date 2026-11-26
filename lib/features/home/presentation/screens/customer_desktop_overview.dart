import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/desktop_workspace.dart';
import '../../../../core/widgets/glass_controls.dart';
import '../../marketplace.dart';
import 'customer_booking_tabs.dart';

class CustomerDesktopOverview extends StatelessWidget {
  const CustomerDesktopOverview({
    super.key,
    required this.bookings,
    required this.onExplore,
    required this.onProperties,
  });
  final List<Booking> bookings;
  final VoidCallback onExplore;
  final VoidCallback onProperties;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final metrics = [
      (
        'New bookings',
        customerTabBookings(bookings, CustomerBookingTab.newBookings).length,
        Icons.receipt_long_outlined,
      ),
      (
        'In progress',
        customerTabBookings(bookings, CustomerBookingTab.inProgress).length,
        Icons.timelapse_rounded,
      ),
      (
        'Completed',
        customerTabBookings(bookings, CustomerBookingTab.completed).length,
        Icons.task_alt_rounded,
      ),
      (
        'Unread updates',
        bookings.where((booking) => booking.hasUnreadUpdates).length,
        Icons.notifications_none_rounded,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          solid: true,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your service overview', style: text.headlineLarge),
                    const SizedBox(height: EdenSpacing.gap),
                    Text(
                      'Track your requests, review progress and plan your next home service.',
                      style: text.bodyMedium?.copyWith(
                        color: EdenDarkColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: EdenSpacing.section),
              SizedBox(
                width: EdenDesktopLayout.actionWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: onExplore,
                      icon: const Icon(Icons.add),
                      label: const Text('Explore services'),
                    ),
                    const SizedBox(height: EdenSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: onProperties,
                      icon: const Icon(Icons.home_work_outlined),
                      label: const Text('Manage properties'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: EdenSpacing.section),
        EdenDesktopGrid(
          minimumWidth: 170,
          maximumColumns: 4,
          children: [
            for (final (label, count, icon) in metrics)
              GlassCard(
                solid: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: EdenDarkColors.accent),
                    const SizedBox(height: EdenSpacing.screen),
                    Text('$count', style: text.headlineLarge),
                    const SizedBox(height: EdenSpacing.xs),
                    Text(
                      label,
                      style: text.bodyMedium?.copyWith(
                        color: EdenDarkColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
