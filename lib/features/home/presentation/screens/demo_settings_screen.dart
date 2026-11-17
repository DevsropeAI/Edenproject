import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/auth_state.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../preferences.dart';
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
});

final demoSettingsProvider =
    NotifierProvider<DemoSettingsNotifier, DemoSettings>(
      DemoSettingsNotifier.new,
    );

class DemoSettingsNotifier extends Notifier<DemoSettings> {
  @override
  DemoSettings build() {
    final saved = ref.watch(preferencesProvider).value ?? const {};
    return (
      notifications: saved['notifications'] as bool? ?? true,
      available: saved['available'] as bool? ?? true,
      snowProperty: saved['snowProperty'] as int?,
      threshold: saved['threshold'] as int? ?? 2,
    );
  }

  void update({
    bool? notifications,
    bool? available,
    int? property,
    int? threshold,
    bool clearSnow = false,
  }) {
    savePreferences(ref, {
      if (notifications != null) 'notifications': notifications,
      if (available != null) 'available': available,
      if (clearSnow || property != null)
        'snowProperty': clearSnow ? null : property,
      if (threshold != null) 'threshold': threshold,
    });
  }
}

class DemoSettingsScreen extends ConsumerStatefulWidget {
  const DemoSettingsScreen({super.key, required this.section});
  final SettingsSection section;

  @override
  ConsumerState<DemoSettingsScreen> createState() => _DemoSettingsScreenState();
}

final payoutRequestedProvider = NotifierProvider<PayoutRequested, double>(
  PayoutRequested.new,
);

class PayoutRequested extends Notifier<double> {
  @override
  double build() {
    ref.watch(activeAccountIdProvider);
    return 0;
  }

  void request(double amount) => state += amount;
}

final supportRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final response = await ref.watch(apiClientProvider).get('/support');
      return (response.data as List).cast<Map<String, dynamic>>();
    });

class _DemoSettingsScreenState extends ConsumerState<DemoSettingsScreen> {
  final _ticket = TextEditingController();
  final _supportForm = GlobalKey<FormState>();
  bool _sending = false;
  int? _property;

  Future<void> _sendTicket() async {
    if (!_supportForm.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(apiClientProvider)
          .post('/support', data: {'description': _ticket.text.trim()});
      if (!mounted) return;
      _ticket.clear();
      ref.invalidate(supportRequestsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

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
    final contractor = ref
        .watch(authProvider)
        .maybeWhen(
          authenticated: (user) => user.role == 'contractor',
          orElse: () => false,
        );
    final properties = ref.watch(propertiesProvider);
    final selected = properties
        .where((item) => item.id == (_property ?? settings.snowProperty))
        .firstOrNull;
    final bookings = ref.watch(bookingsProvider);
    final notices = [
      if (!contractor && section == SettingsSection.preferences)
        for (final booking in bookings)
          for (final notice in booking.customerNotices)
            (booking: booking, notice: notice),
    ]..sort((a, b) => b.notice.at.compareTo(a.notice.at));
    final completed = bookings.where(
      (item) => item.status == JobStatus.completed,
    );
    final payout = ref.watch(payoutRequestedProvider);
    final gross = completed.fold<double>(
      0,
      (total, booking) => total + booking.total,
    );

    return MarketPage(
      dark: true,
      customerTab: !contractor && section == SettingsSection.support ? 2 : null,
      darkNavigation: contractor && section == SettingsSection.wallet
          ? const ContractorNavigation(index: 1)
          : null,
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
          solid: section == SettingsSection.support,
          children: switch (section) {
            SettingsSection.preferences => [
              SwitchListTile(
                title: const Text('In-app booking alerts'),
                value: settings.notifications,
                onChanged: (value) => notifier.update(notifications: value),
              ),
              const Text('Your preference is saved to your account.'),
              if (!contractor) ...[
                const Divider(),
                const MarketHeading('Order updates'),
                if (notices.isEmpty)
                  const Text(
                    'Updates will appear here when a contractor accepts a booking, heads your way, or submits work.',
                  ),
                for (final entry in notices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(orderNoticeText(entry.notice.status)),
                    subtitle: Text(
                      '#${entry.booking.id} · ${entry.booking.service.label}\n'
                      '${MaterialLocalizations.of(context).formatShortDate(entry.notice.at)} · '
                      '${TimeOfDay.fromDateTime(entry.notice.at).format(context)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/bookings/${entry.booking.id}'),
                  ),
              ],
            ],
            SettingsSection.verification => [
              SwitchListTile(
                title: const Text('Available for new jobs'),
                value: settings.available,
                onChanged: (value) => notifier.update(available: value),
              ),
            ],
            SettingsSection.wallet => [
              Text('Demo payout queued: CAD ${payout.toStringAsFixed(2)}'),
              FilledButton(
                onPressed: gross <= payout
                    ? null
                    : () {
                        ref
                            .read(payoutRequestedProvider.notifier)
                            .request(gross - payout);
                      },
                child: const Text('Request demo payout'),
              ),
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
                onPressed: _sending ? null : _sendTicket,
                child: const Text('Send support request'),
              ),
              const Divider(),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.forum_outlined),
                title: Text('Your requests'),
              ),
              ...ref
                  .watch(supportRequestsProvider)
                  .when(
                    data: (tickets) => [
                      if (tickets.isEmpty)
                        const Text(
                          'Support requests you send will appear here.',
                        ),
                      for (final ticket in tickets)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(ticket['description'] as String),
                          subtitle: Text(ticket['status'] as String),
                        ),
                    ],
                    loading: () => const [LinearProgressIndicator()],
                    error: (error, _) => [
                      Text(apiError(error)),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(supportRequestsProvider),
                        child: const Text('Reload requests'),
                      ),
                    ],
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
              if (properties
                      .where((property) => property.id == settings.snowProperty)
                      .firstOrNull
                  case final property?)
                OutlinedButton(
                  onPressed: () async {
                    final existing = bookings.any(
                      (booking) =>
                          booking.property.id == property.id &&
                          booking.notes == 'Proposed from a sample snowfall.',
                    );
                    if (existing) {
                      context.go('/bookings');
                      return;
                    }
                    final placed = await ref
                        .read(bookingsProvider.notifier)
                        .place(
                          property,
                          Service.snow,
                          DateTime.now().add(const Duration(days: 1)),
                          'Proposed from a sample snowfall.',
                          false,
                        );
                    if (placed && context.mounted) context.go('/bookings');
                  },
                  child: Text('Simulate ${settings.threshold} in of snow'),
                ),
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

// import 'package:flutter/material.dart';
// import 'package:go_router/go_router.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';

// import '../../../../core/network/api_client.dart';
// import '../../../auth/data/repositories/auth_repository.dart';
// import '../../../auth/providers/auth_provider.dart';
// import '../../preferences.dart';
// import '../../marketplace.dart';
// import 'marketplace_screens.dart';

// enum SettingsSection {
//   support('Help & support', Icons.support_agent),
//   preferences('Notifications', Icons.notifications_outlined),
//   automatic('Automatic snow removal', Icons.ac_unit),
//   wallet('Earnings', Icons.account_balance_wallet_outlined),
//   verification('Contractor availability', Icons.event_available_outlined);

//   const SettingsSection(this.label, this.icon);
//   final String label;
//   final IconData icon;
// }

// typedef DemoSettings = ({
//   bool notifications,
//   bool available,
//   int? snowProperty,
//   int threshold,
// });

// final demoSettingsProvider =
//     NotifierProvider<DemoSettingsNotifier, DemoSettings>(
//       DemoSettingsNotifier.new,
//     );

// class DemoSettingsNotifier extends Notifier<DemoSettings> {
//   @override
//   DemoSettings build() {
//     final saved = ref.watch(preferencesProvider).value ?? const {};
//     return (
//       notifications: saved['notifications'] as bool? ?? true,
//       available: saved['available'] as bool? ?? true,
//       snowProperty: saved['snowProperty'] as int?,
//       threshold: saved['threshold'] as int? ?? 2,
//     );
//   }

//   void update({
//     bool? notifications,
//     bool? available,
//     int? property,
//     int? threshold,
//     bool clearSnow = false,
//   }) {
//     savePreferences(ref, {
//       if (notifications != null) 'notifications': notifications,
//       if (available != null) 'available': available,
//       if (clearSnow || property != null)
//         'snowProperty': clearSnow ? null : property,
//       if (threshold != null) 'threshold': threshold,
//     });
//   }
// }

// class DemoSettingsScreen extends ConsumerStatefulWidget {
//   const DemoSettingsScreen({super.key, required this.section});
//   final SettingsSection section;

//   @override
//   ConsumerState<DemoSettingsScreen> createState() => _DemoSettingsScreenState();
// }

// final payoutRequestedProvider = NotifierProvider<PayoutRequested, double>(
//   PayoutRequested.new,
// );

// class PayoutRequested extends Notifier<double> {
//   @override
//   double build() {
//     ref.watch(activeAccountIdProvider);
//     return 0;
//   }

//   void request(double amount) => state += amount;
// }

// final supportRequestsProvider =
//     FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
//       final response = await ref.watch(apiClientProvider).get('/support');
//       return (response.data as List).cast<Map<String, dynamic>>();
//     });

// class _DemoSettingsScreenState extends ConsumerState<DemoSettingsScreen> {
//   final _ticket = TextEditingController();
//   final _supportForm = GlobalKey<FormState>();
//   bool _sending = false;
//   int? _property;

//   Future<void> _sendTicket() async {
//     if (!_supportForm.currentState!.validate()) return;
//     setState(() => _sending = true);
//     try {
//       await ref
//           .read(apiClientProvider)
//           .post('/support', data: {'description': _ticket.text.trim()});
//       if (!mounted) return;
//       _ticket.clear();
//       ref.invalidate(supportRequestsProvider);
//     } catch (error) {
//       if (mounted) {
//         ScaffoldMessenger.of(context)
//             .showSnackBar(SnackBar(content: Text(apiError(error))));
//       }
//     } finally {
//       if (mounted) setState(() => _sending = false);
//     }
//   }

//   int? _threshold;

//   @override
//   void dispose() {
//     _ticket.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final settings = ref.watch(demoSettingsProvider);
//     final notifier = ref.read(demoSettingsProvider.notifier);
//     final section = widget.section;
//     final properties = ref.watch(propertiesProvider);
//     final selected = properties
//         .where((item) => item.id == (_property ?? settings.snowProperty))
//         .firstOrNull;
//     final bookings = ref.watch(bookingsProvider);
//     final completed = bookings.where(
//       (item) => item.status == JobStatus.completed,
//     );
//     final payout = ref.watch(payoutRequestedProvider);
//     final gross = completed.fold<double>(
//       0,
//       (total, booking) => total + booking.total,
//     );

//     return MarketPage(
//       customerTheme: true,
//       customerTab: section == SettingsSection.support ? 2 : null,
//       title: section.label,
//       children: [
//         MarketBanner(section.label, switch (section) {
//           SettingsSection.support => 'Describe a booking or account issue.',
//           SettingsSection.preferences =>
//             'Choose whether to receive booking updates.',
//           SettingsSection.automatic =>
//             'Set a snowfall threshold for a saved property.',
//           SettingsSection.wallet =>
//             'Review completed jobs and estimated earnings.',
//           SettingsSection.verification =>
//             'Manage whether you are available for new jobs.',
//         }, section.icon),
//         MarketCard(
//           solid: section == SettingsSection.support,
//           children: switch (section) {
//             SettingsSection.preferences => [
//               SwitchListTile(
//                 title: const Text('Booking updates'),
//                 value: settings.notifications,
//                 onChanged: (value) => notifier.update(notifications: value),
//               ),
//               const Text('Your preference is saved to your account.'),
//             ],
//             SettingsSection.verification => [
//               SwitchListTile(
//                 title: const Text('Available for new jobs'),
//                 value: settings.available,
//                 onChanged: (value) => notifier.update(available: value),
//               ),
//             ],
//             SettingsSection.wallet => [
//               Text('Demo payout queued: CAD ${payout.toStringAsFixed(2)}'),
//               FilledButton(
//                 onPressed: gross <= payout
//                     ? null
//                     : () {
//                         ref
//                             .read(payoutRequestedProvider.notifier)
//                             .request(gross - payout);
//                       },
//                 child: const Text('Request demo payout'),
//               ),
//               Text('Completed jobs: ${completed.length}'),
//               Text('Completed order total: CAD ${gross.toStringAsFixed(2)}'),
//               for (final booking in completed)
//                 ListTile(
//                   contentPadding: EdgeInsets.zero,
//                   title: Text(booking.service.label),
//                   subtitle: Text(booking.property.name),
//                   trailing: Text('CAD ${booking.total.toStringAsFixed(2)}'),
//                 ),
//               const Text(
//                 'Payout balances and transfers will appear when payments are connected.',
//               ),
//             ],
//             SettingsSection.support => [
//               Form(
//                 key: _supportForm,
//                 child: TextFormField(
//                   controller: _ticket,
//                   maxLines: 4,
//                   maxLength: 1000,
//                   decoration: const InputDecoration(
//                     labelText: 'Describe the issue',
//                   ),
//                   validator: (value) => (value ?? '').trim().isEmpty
//                       ? 'Enter a description'
//                       : null,
//                 ),
//               ),
//               FilledButton(
//                 onPressed: _sending ? null : _sendTicket,
//                 child: const Text('Send support request'),
//               ),
//               const Divider(),
//               const ListTile(
//                 contentPadding: EdgeInsets.zero,
//                 leading: Icon(Icons.forum_outlined),
//                 title: Text('Your requests'),
//               ),
//               ...ref
//                   .watch(supportRequestsProvider)
//                   .when(
//                     data: (tickets) => [
//                       if (tickets.isEmpty)
//                         const Text(
//                           'Support requests you send will appear here.',
//                         ),
//                       for (final ticket in tickets)
//                         ListTile(
//                           contentPadding: EdgeInsets.zero,
//                           title: Text(ticket['description'] as String),
//                           subtitle: Text(ticket['status'] as String),
//                         ),
//                     ],
//                     loading: () => const [LinearProgressIndicator()],
//                     error: (error, _) => [
//                       Text(apiError(error)),
//                       TextButton(
//                         onPressed: () =>
//                             ref.invalidate(supportRequestsProvider),
//                         child: const Text('Reload requests'),
//                       ),
//                     ],
//                   ),
//             ],
//             SettingsSection.automatic => [
//               if (properties.isEmpty)
//                 const Text(
//                   'Add a property before setting a snowfall threshold.',
//                 ),
//               if (properties.isNotEmpty) ...[
//                 DropdownButtonFormField<int>(
//                   key: ValueKey(selected?.id),
//                   initialValue: selected?.id,
//                   isExpanded: true,
//                   decoration: const InputDecoration(labelText: 'Property'),
//                   items: [
//                     for (final property in properties)
//                       DropdownMenuItem(
//                         value: property.id,
//                         child: Text(property.name),
//                       ),
//                   ],
//                   onChanged: (value) => setState(() => _property = value),
//                 ),
//                 DropdownButtonFormField<int>(
//                   initialValue: _threshold ?? settings.threshold,
//                   decoration: const InputDecoration(
//                     labelText: 'Snowfall threshold',
//                   ),
//                   items: [
//                     for (final inches in [1, 2, 3, 4, 6])
//                       DropdownMenuItem(
//                         value: inches,
//                         child: Text('$inches in'),
//                       ),
//                   ],
//                   onChanged: (value) => setState(() => _threshold = value),
//                 ),
//                 FilledButton(
//                   onPressed: selected == null
//                       ? null
//                       : () {
//                           notifier.update(
//                             property: selected.id,
//                             threshold: _threshold ?? settings.threshold,
//                           );
//                           ScaffoldMessenger.of(context).showSnackBar(
//                             const SnackBar(
//                               content: Text('Snow service preference saved'),
//                             ),
//                           );
//                         },
//                   child: const Text('Save preference'),
//                 ),
//               ],
//               if (properties
//                       .where((property) => property.id == settings.snowProperty)
//                       .firstOrNull
//                   case final property?)
//                 OutlinedButton(
//                   onPressed: () async {
//                     final existing = bookings.any(
//                       (booking) =>
//                           booking.property.id == property.id &&
//                           booking.notes == 'Proposed from a sample snowfall.',
//                     );
//                     if (existing) {
//                       context.go('/bookings');
//                       return;
//                     }
//                     final placed = await ref
//                         .read(bookingsProvider.notifier)
//                         .place(
//                           property,
//                           Service.snow,
//                           DateTime.now().add(const Duration(days: 1)),
//                           'Proposed from a sample snowfall.',
//                           false,
//                         );
//                     if (placed && context.mounted) context.go('/bookings');
//                   },
//                   child: Text('Simulate ${settings.threshold} in of snow'),
//                 ),
//               if (settings.snowProperty != null)
//                 TextButton(
//                   onPressed: () {
//                     notifier.update(clearSnow: true);
//                     setState(() => _property = null);
//                   },
//                   child: const Text('Remove saved preference'),
//                 ),
//               const Text(
//                 'Automatic orders require a connected weather and scheduling service.',
//               ),
//             ],
//           },
//         ),
//       ],
//     );
//   }
// }
