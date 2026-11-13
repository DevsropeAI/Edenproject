import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../marketplace.dart';
import 'marketplace_screens.dart';

enum AccountSection {
  reviews('Reviews', Icons.star_outline),
  payments('Payments & refunds', Icons.receipt_long_outlined),
  recurring('Weekly service requests', Icons.event_repeat),
  schedule('Hours & service radius', Icons.schedule);

  const AccountSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

typedef LocalAccount = ({
  Map<int, int> tips,
  Set<int> refunds,
  Set<int> paused,
  TimeOfDay opens,
  TimeOfDay closes,
  int radius,
});

final localAccountProvider =
    NotifierProvider<LocalAccountNotifier, LocalAccount>(
      LocalAccountNotifier.new,
    );

class LocalAccountNotifier extends Notifier<LocalAccount> {
  @override
  LocalAccount build() => (
    tips: const {},
    refunds: const {},
    paused: const {},
    opens: const TimeOfDay(hour: 9, minute: 0),
    closes: const TimeOfDay(hour: 17, minute: 0),
    radius: 15,
  );

  void update({
    Map<int, int>? tips,
    Set<int>? refunds,
    Set<int>? paused,
    TimeOfDay? opens,
    TimeOfDay? closes,
    int? radius,
  }) {
    state = (
      tips: tips ?? state.tips,
      refunds: refunds ?? state.refunds,
      paused: paused ?? state.paused,
      opens: opens ?? state.opens,
      closes: closes ?? state.closes,
      radius: radius ?? state.radius,
    );
  }
}

class AccountExtrasScreen extends ConsumerWidget {
  const AccountExtrasScreen({super.key, required this.section});
  final AccountSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(bookingsProvider);
    final settings = ref.watch(localAccountProvider);
    final notifier = ref.read(localAccountProvider.notifier);
    final matching = bookings.where(
      (booking) => switch (section) {
        AccountSection.reviews => booking.rating != null,
        AccountSection.payments => booking.demoPaid,
        AccountSection.recurring => booking.recurring,
        AccountSection.schedule => false,
      },
    );
    return MarketPage(
      title: section.label,
      children: [
        MarketBanner(section.label, switch (section) {
          AccountSection.reviews =>
            'Ratings and written feedback from completed jobs.',
          AccountSection.payments =>
            'Demo card activity and refund requests for this session.',
          AccountSection.recurring =>
            'Manage your saved weekly service preferences.',
          AccountSection.schedule =>
            'Set your typical working hours and travel distance.',
        }, section.icon),
        if (section == AccountSection.schedule)
          MarketCard(
            children: [
              for (final (label, time, opening) in [
                ('Start time', settings.opens, true),
                ('End time', settings.closes, false),
              ])
                OutlinedButton(
                  onPressed: () async {
                    final selected = await showTimePicker(
                      context: context,
                      initialTime: time,
                    );
                    if (selected == null || !context.mounted) return;
                    final start = opening ? selected : settings.opens;
                    final end = opening ? settings.closes : selected;
                    if (start.hour * 60 + start.minute >=
                        end.hour * 60 + end.minute) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('End time must be after start time.'),
                        ),
                      );
                      return;
                    }
                    notifier.update(opens: start, closes: end);
                  },
                  child: Text('$label · ${time.format(context)}'),
                ),
              Text('Service radius · ${settings.radius} km'),
              Slider(
                value: settings.radius.toDouble(),
                min: 5,
                max: 50,
                divisions: 9,
                label: '${settings.radius} km',
                onChanged: (value) => notifier.update(radius: value.round()),
              ),
            ],
          )
        else ...[
          for (final booking in matching.isEmpty ? [_sampleBooking] : matching)
            MarketCard(
              children: [
                if (booking.id == _sampleBooking.id)
                  const Chip(label: Text('Sample activity')),
                Text(
                  booking.service.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  booking.id == _sampleBooking.id
                      ? booking.property.name
                      : '${booking.property.name} · Booking #${booking.id}',
                ),
                if (section == AccountSection.reviews) ...[
                  Text('${booking.rating}/5 stars'),
                  if (booking.review.isNotEmpty) Text(booking.review),
                ],
                if (section == AccountSection.payments) ...[
                  Text(
                    'Demo card approved · CAD ${booking.total.toStringAsFixed(2)}',
                  ),
                  if (settings.tips[booking.id] case final tip?)
                    Text('Demo tip · CAD $tip'),
                  if (settings.refunds.contains(booking.id))
                    const Text('Refund requested · Pending demo review'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (booking.status == JobStatus.completed &&
                          !settings.tips.containsKey(booking.id) &&
                          !settings.refunds.contains(booking.id))
                        OutlinedButton(
                          onPressed: () async {
                            final tip = await showDialog<int>(
                              context: context,
                              builder: (dialog) => SimpleDialog(
                                title: const Text('Add a demo tip'),
                                children: [
                                  for (final amount in [5, 10, 15])
                                    SimpleDialogOption(
                                      onPressed: () =>
                                          Navigator.pop(dialog, amount),
                                      child: Text('CAD $amount'),
                                    ),
                                ],
                              ),
                            );
                            if (tip == null || !context.mounted) return;
                            notifier.update(
                              tips: {
                                ...ref.read(localAccountProvider).tips,
                                booking.id: tip,
                              },
                            );
                          },
                          child: const Text('Add demo tip'),
                        ),
                      if (!settings.refunds.contains(booking.id))
                        OutlinedButton(
                          onPressed: () => notifier.update(
                            refunds: {...settings.refunds, booking.id},
                          ),
                          child: const Text('Request demo refund'),
                        ),
                    ],
                  ),
                ],
                if (section == AccountSection.recurring)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Weekly preference active'),
                    subtitle: const Text('Saved locally for this session'),
                    value: !settings.paused.contains(booking.id),
                    onChanged: (enabled) {
                      final paused = {...settings.paused};
                      if (enabled) {
                        paused.remove(booking.id);
                      } else {
                        paused.add(booking.id);
                      }
                      notifier.update(paused: paused);
                    },
                  ),
                if (booking.id != _sampleBooking.id)
                  TextButton(
                    onPressed: () => context.push('/bookings/${booking.id}'),
                    child: const Text('View booking'),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

final _sampleBooking = Booking(
  id: -1,
  property: const Property(-1, 'Maple House', 'Toronto', 'Standard', ''),
  service: Service.snow,
  date: DateTime(2026, 1, 10, 9),
  total: 50.85,
  notes: '',
  recurring: true,
  demoPaid: true,
  status: JobStatus.completed,
  rating: 5,
  review: 'The driveway and front walkway were cleared before I left for work.',
);
