import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../preferences.dart';
import '../../marketplace.dart';
import 'marketplace_screens.dart';
import 'payments_screen.dart';

enum AccountSection {
  reviews('Reviews', Icons.star_outline),
  payments('Payments & refunds', Icons.receipt_long_outlined),
  recurring('Weekly service requests', Icons.event_repeat),
  schedule('Hours & service radius', Icons.schedule);

  const AccountSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

typedef LocalAccount = ({TimeOfDay opens, TimeOfDay closes, int radius});

final localAccountProvider =
    NotifierProvider<LocalAccountNotifier, LocalAccount>(
      LocalAccountNotifier.new,
    );

class LocalAccountNotifier extends Notifier<LocalAccount> {
  @override
  LocalAccount build() {
    final saved = ref.watch(preferencesProvider).value ?? const {};
    TimeOfDay time(String key, int fallback) {
      final minutes = saved[key] as int? ?? fallback;
      return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    }

    return (
      opens: time('opens', 540),
      closes: time('closes', 1020),
      radius: saved['radius'] as int? ?? 15,
    );
  }

  void previewRadius(int radius) =>
      state = (opens: state.opens, closes: state.closes, radius: radius);

  void update({TimeOfDay? opens, TimeOfDay? closes, int? radius}) {
    if (opens != null || closes != null || radius != null) {
      savePreferences(ref, {
        if (opens != null) 'opens': opens.hour * 60 + opens.minute,
        if (closes != null) 'closes': closes.hour * 60 + closes.minute,
        if (radius != null) 'radius': radius,
      });
    }
    state = (
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
    if (section == AccountSection.payments) return const PaymentsScreen();
    final bookings = ref.watch(bookingsProvider);
    final settings = ref.watch(localAccountProvider);
    final notifier = ref.read(localAccountProvider.notifier);
    final matching = bookings.where(
      (booking) => switch (section) {
        AccountSection.reviews => booking.rating != null,
        AccountSection.payments => false,
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
            'Review booking payments and refund requests.',
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
                onChanged: (value) => notifier.previewRadius(value.round()),
                onChangeEnd: (value) => notifier.update(radius: value.round()),
              ),
            ],
          )
        else ...[
          for (final booking in matching)
            MarketCard(
              children: [
                Text(
                  booking.service.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${booking.property.name} · Booking #${booking.id}'),
                if (section == AccountSection.reviews) ...[
                  Text('${booking.rating}/5 stars'),
                  if (booking.review.isNotEmpty) Text(booking.review),
                ],
                if (section == AccountSection.recurring)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Weekly preference active'),
                    subtitle: const Text('Saved to your account'),
                    value: !booking.paused,
                    onChanged: (active) => ref
                        .read(bookingsProvider.notifier)
                        .setWeeklyPaused(booking.id, !active),
                  ),
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
