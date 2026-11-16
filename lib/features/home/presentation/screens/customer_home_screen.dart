import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../marketplace.dart';
import 'marketplace_screens.dart';

class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(serviceCatalogProvider);
    return MarketPage(
      title: 'Eden',
      nav: 0,
      children: [
        const MarketBanner(
          'Home services made easy',
          'Get a quote and book help for your home or property.',
          Icons.eco_outlined,
        ),
        Text('Explore services', style: Theme.of(context).textTheme.titleLarge),
        if (catalog.isLoading) const LinearProgressIndicator(),
        if (catalog.hasError)
          TextButton(
            onPressed: () => ref.invalidate(serviceCatalogProvider),
            child: const Text('Retry loading services'),
          ),
        if (catalog.value?.isEmpty == true)
          const Text('No services are currently available.'),
        for (final (service, icon, description) in [
          (Service.snow, Icons.ac_unit, 'Clear your driveway and entrance'),
          (Service.lawn, Icons.grass, 'Keep your lawn neat and tidy'),
          (
            Service.cleaning,
            Icons.cleaning_services_outlined,
            'Give your home a fresh start',
          ),
        ])
          if (catalog.value?.containsKey(service) == true)
            MarketCard(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(icon)),
                  title: Text(service.label),
                  subtitle: Text(description),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/properties', extra: service),
                ),
              ],
            ),
        OutlinedButton.icon(
          onPressed: () => context.push('/properties'),
          icon: const Icon(Icons.home_work_outlined),
          label: const Text('Manage properties'),
        ),
      ],
    );
  }
}
