import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/glass_controls.dart';
import '../../marketplace.dart';
import 'marketplace_screens.dart';

class ExploreServicesScreen extends ConsumerWidget {
  const ExploreServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(serviceCatalogProvider);
    final details = ref.watch(serviceDetailsProvider).value ?? const <Map<String,dynamic>>[];
    final services = [for(final service in catalog.value?.keys ?? <Service>[])
      (service,service.isSnow ? Icons.ac_unit : Icons.home_repair_service_outlined,
        details.where((row)=>row['id']==service.name).firstOrNull?['description'] as String? ?? 'Home services')];
    return MarketPage(
      title: 'Explore services',
      dark: true,
      children: [
        const MarketBanner(
          'What do you need done today?',
          'Book and manage services for your home.',
          Icons.home_work_outlined,
        ),
        Builder(
          builder: (context) => Text(
            'Explore services',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (catalog.isLoading)
          const ShimmerBox(height: EdenSpacing.control * 2),
        if (catalog.hasError)
          TextButton(
            onPressed: () => ref.invalidate(serviceCatalogProvider),
            child: const Text('Retry loading services'),
          ),
        if (catalog.value?.isEmpty == true)
          EmptyState(
            icon: Icons.home_repair_service_outlined,
            message: 'No services are available right now.',
            action: TextButton(
              onPressed: () => ref.invalidate(serviceCatalogProvider),
              child: const Text('Refresh services'),
            ),
          ),
        if (services.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 300 ? 1 : 2;
              final width =
                  (constraints.maxWidth - EdenSpacing.gap * (columns - 1)) /
                  columns;
              return Wrap(
                spacing: EdenSpacing.gap,
                runSpacing: EdenSpacing.gap,
                children: [
                  for (final (service, icon, description) in services)
                    SizedBox(
                      width: width,
                      child: GlassCard(
                        child: InkWell(
                          onTap: () =>
                              context.push('/properties', extra: service),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: EdenSpacing.control,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(icon),
                                const SizedBox(height: EdenSpacing.gap),
                                Text(
                                  service.label,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: EdenSpacing.xs),
                                Text(
                                  description,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        SecondaryButton(
          onPressed: () => context.push('/properties'),
          icon: Icons.home_work_outlined,
          label: 'Manage properties',
        ),
      ],
    );
  }
}

