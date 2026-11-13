import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../marketplace.dart';
import 'marketplace_screens.dart';

enum SettingsSection {
  support('Help & support', Icons.support_agent),
  preferences('Notifications', Icons.notifications_outlined),
  automatic('Automatic snow removal', Icons.ac_unit),
  wallet('Earnings', Icons.account_balance_wallet_outlined),
  verification('Contractor availability', Icons.event_available_outlined);

  const SettingsSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

typedef DemoSettings = ({
  bool notifications,
  bool available,
  int? snowProperty,
  int threshold,
  List<String> tickets,
});

final demoSettingsProvider =
    NotifierProvider<DemoSettingsNotifier, DemoSettings>(
      DemoSettingsNotifier.new,
    );

class DemoSettingsNotifier extends Notifier<DemoSettings> {
  @override
  DemoSettings build() => (
    notifications: true,
    available: true,
    snowProperty: null,
    threshold: 2,
    tickets: const [],
  );

  void update({
    bool? notifications,
    bool? available,
    int? property,
    int? threshold,
    String? ticket,
    bool clearSnow = false,
  }) {
    state = (
      notifications: notifications ?? state.notifications,
      available: available ?? state.available,
      snowProperty: clearSnow ? null : property ?? state.snowProperty,
      threshold: threshold ?? state.threshold,
      tickets: ticket == null ? state.tickets : [...state.tickets, ticket],
    );
  }
}

class DemoSettingsScreen extends ConsumerStatefulWidget {
  const DemoSettingsScreen({super.key, required this.section});
  final SettingsSection section;

  @override
  ConsumerState<DemoSettingsScreen> createState() => _DemoSettingsScreenState();
}

class _DemoSettingsScreenState extends ConsumerState<DemoSettingsScreen> {
  final _ticket = TextEditingController();
  final _supportForm = GlobalKey<FormState>();
  int? _property;
  int? _threshold;

  @override
  void dispose() {
    _ticket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(demoSettingsProvider);
    final notifier = ref.read(demoSettingsProvider.notifier);
    final section = widget.section;
    final properties = ref.watch(propertiesProvider);
    final selected = properties
        .where((item) => item.id == (_property ?? settings.snowProperty))
        .firstOrNull;
    final bookings = ref.watch(bookingsProvider);
    final completed = bookings.where(
      (item) => item.status == JobStatus.completed,
    );
    final gross = completed.fold<double>(
      0,
      (total, booking) => total + booking.total,
    );

    return MarketPage(
      title: section.label,
      children: [
        MarketBanner(section.label, switch (section) {
          SettingsSection.support => 'Describe a booking or account issue.',
          SettingsSection.preferences =>
            'Choose whether to receive booking updates.',
          SettingsSection.automatic =>
            'Set a snowfall threshold for a saved property.',
          SettingsSection.wallet =>
            'Review completed jobs and estimated earnings.',
          SettingsSection.verification =>
            'Manage whether you are available for new jobs.',
        }, section.icon),
        MarketCard(
          children: switch (section) {
            SettingsSection.preferences => [
              SwitchListTile(
                title: const Text('Booking updates'),
                value: settings.notifications,
                onChanged: (value) => notifier.update(notifications: value),
              ),
              const Text(
                'This demo saves your preference for the current session.',
              ),
            ],
            SettingsSection.verification => [
              SwitchListTile(
                title: const Text('Available for new jobs'),
                value: settings.available,
                onChanged: (value) => notifier.update(available: value),
              ),
            ],
            SettingsSection.wallet => [
              Text('Completed jobs: ${completed.length}'),
              Text('Completed order total: CAD ${gross.toStringAsFixed(2)}'),
              for (final booking in completed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(booking.service.label),
                  subtitle: Text(booking.property.name),
                  trailing: Text('CAD ${booking.total.toStringAsFixed(2)}'),
                ),
              const Text(
                'Payout balances and transfers will appear when payments are connected.',
              ),
            ],
            SettingsSection.support => [
              Form(
                key: _supportForm,
                child: TextFormField(
                  controller: _ticket,
                  maxLines: 4,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Describe the issue',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter a description'
                      : null,
                ),
              ),
              FilledButton(
                onPressed: () {
                  if (!_supportForm.currentState!.validate()) return;
                  notifier.update(ticket: _ticket.text.trim());
                  _ticket.clear();
                },
                child: const Text('Save support request'),
              ),
              if (settings.tickets.isNotEmpty)
                const Text('Requests saved in this session'),
              for (final ticket in settings.tickets)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(ticket),
                ),
            ],
            SettingsSection.automatic => [
              if (properties.isEmpty)
                const Text(
                  'Add a property before setting a snowfall threshold.',
                ),
              if (properties.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  key: ValueKey(selected?.id),
                  initialValue: selected?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Property'),
                  items: [
                    for (final property in properties)
                      DropdownMenuItem(
                        value: property.id,
                        child: Text(property.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _property = value),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _threshold ?? settings.threshold,
                  decoration: const InputDecoration(
                    labelText: 'Snowfall threshold',
                  ),
                  items: [
                    for (final inches in [1, 2, 3, 4, 6])
                      DropdownMenuItem(
                        value: inches,
                        child: Text('$inches in'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _threshold = value),
                ),
                FilledButton(
                  onPressed: selected == null
                      ? null
                      : () {
                          notifier.update(
                            property: selected.id,
                            threshold: _threshold ?? settings.threshold,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Snow service preference saved'),
                            ),
                          );
                        },
                  child: const Text('Save preference'),
                ),
              ],
              if (settings.snowProperty != null)
                TextButton(
                  onPressed: () {
                    notifier.update(clearSnow: true);
                    setState(() => _property = null);
                  },
                  child: const Text('Remove saved preference'),
                ),
              const Text(
                'Automatic orders require a connected weather and scheduling service.',
              ),
            ],
          },
        ),
      ],
    );
  }
}
