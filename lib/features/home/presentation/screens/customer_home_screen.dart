import '../../../../core/widgets/desktop_workspace.dart';
import 'customer_desktop_overview.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/glass_controls.dart';
import '../../marketplace.dart';
import 'marketplace_screens.dart';
import 'customer_booking_tabs.dart';

class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MarketPage(
    title: EdenDesktopLayout.enabled(context) ? 'Overview' : 'Eden',
    dark: true,
    darkNavigation: const CustomerNavigation(index: 0),
    children: [
      if (EdenDesktopLayout.enabled(context))
        CustomerDesktopOverview(
          bookings: ref.watch(bookingsProvider),
          onExplore: () => context.push('/explore-services'),
          onProperties: () => context.push('/properties'),
        )
      else ...[
        const MarketBanner(
          'Your home services',
          'Follow your bookings or find your next service.',
          Icons.home_work_outlined,
        ),
        SecondaryButton(
          onPressed: () => context.push('/explore-services'),
          icon: Icons.grid_view_rounded,
          label: 'Explore services',
        ),
      ],
      CustomerBookingTabs(
        bookings: ref.watch(bookingsProvider),
        onOpen: (booking) => context.push('/bookings/${booking.id}'),
        onRefresh: () => ref.read(bookingsProvider.notifier).refresh(),
        onBrowse: () => context.push('/explore-services'),
      ),
      if (!EdenDesktopLayout.enabled(context))
        SecondaryButton(
          onPressed: () => context.push('/properties'),
          icon: Icons.home_work_outlined,
          label: 'Manage properties',
        ),
    ],
  );
}
