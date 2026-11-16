import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_client.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../marketplace.dart';
import 'marketplace_screens.dart';

final _paymentsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  if (ref.watch(activeAccountIdProvider) == null) return {};
  final result = await ref.watch(apiClientProvider).get('/payments');
  return Map<String, dynamic>.from(result.data as Map);
});

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  bool _busy = false;

  Future<void> _submit(int id, String action, {int? amount}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final response = await ref
          .read(apiClientProvider)
          .post(
            '/payments/$id',
            data: {'action': action, if (amount != null) 'amountCents': amount},
          );
      if (!mounted) return;
      if (response.data['url'] case final String url) {
        final uri = Uri.parse(url);
        if (uri.scheme != 'https' ||
            !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw StateError('Could not open checkout');
        }
      }
      if (mounted) ref.invalidate(_paymentsProvider);
    } catch (error) {
      if (mounted) ref.read(marketplaceFeedbackProvider.notifier).report(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payments = ref.watch(_paymentsProvider);
    final bookings = ref
        .watch(bookingsProvider)
        .where((booking) => booking.status == JobStatus.completed);
    return MarketPage(
      title: 'Payments & refunds',
      children: [
        OutlinedButton(
          onPressed: _busy ? null : () => ref.invalidate(_paymentsProvider),
          child: const Text('Refresh payment status'),
        ),
        ...payments.when(
          loading: () => const [LinearProgressIndicator()],
          error: (error, _) => const [Text('Could not load payments.')],
          data: (data) {
            if (data['enabled'] != true)
              return const [Text('Online payments are unavailable.')];
            final records = (data['records'] as List)
                .cast<Map<String, dynamic>>();
            return [
              if (bookings.isEmpty) const Text('No completed bookings yet.'),
              for (final booking in bookings)
                MarketCard(
                  children: [
                    Text('Booking #${booking.id} · ${booking.service.label}'),
                    Text('CAD ${booking.total.toStringAsFixed(2)}'),
                    for (final record in records.where(
                      (record) => record['bookingId'] == booking.id,
                    ))
                      Text(
                        '${record['kind']} · CAD ${((record['amountCents'] as num) / 100).toStringAsFixed(2)} · ${(record['status'] as String).replaceAll('_', ' ')}',
                      ),
                    if (!records.any(
                      (record) =>
                          record['bookingId'] == booking.id &&
                          record['kind'] == 'service' &&
                          record['status'] != 'pending',
                    ))
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _submit(booking.id, 'pay'),
                        child: const Text('Pay with Stripe'),
                      ),
                    if (records.any(
                      (record) =>
                          record['bookingId'] == booking.id &&
                          record['kind'] == 'service' &&
                          record['status'] == 'paid',
                    )) ...[
                      if (!records.any(
                        (record) =>
                            record['bookingId'] == booking.id &&
                            record['kind'] == 'tip' &&
                            record['status'] != 'pending',
                      ))
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final amount in [500, 1000, 1500])
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _submit(
                                        booking.id,
                                        'tip',
                                        amount: amount,
                                      ),
                                child: Text('Tip CAD ${amount ~/ 100}'),
                              ),
                          ],
                        ),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _submit(booking.id, 'refund'),
                        child: const Text('Request refund'),
                      ),
                    ],
                  ],
                ),
            ];
          },
        ),
      ],
    );
  }
}
