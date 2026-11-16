import 'package:flutter/material.dart';

import 'marketplace_screens.dart';

class IntegrationDemoScreen extends StatelessWidget {
  const IntegrationDemoScreen({super.key});

  static const _flows = [
    (
      'Phone verification',
      'Enter the sample code to verify a demo phone number.',
      'Verify code',
      'Demo phone verified. No SMS was sent.',
      Icons.sms_outlined,
    ),
    (
      'Password reset',
      'Preview the confirmation shown after requesting a reset email.',
      'Preview reset request',
      'Demo reset request confirmed. No email was sent.',
      Icons.lock_reset,
    ),
    (
      'Live tracking',
      'Preview a contractor approaching a sample property.',
      'Simulate location update',
      'Demo location updated. Contractor is 1.2 km away · ETA 4 min.',
      Icons.location_on_outlined,
    ),
    (
      'Notifications',
      'Preview an alert for a booking status change.',
      'Show sample notification',
      'Eden · Your contractor is on the way.',
      Icons.notifications_outlined,
    ),
    (
      'Payment',
      'Preview a CAD 50.85 payment with a sample card.',
      'Simulate payment',
      'Demo payment approved · CAD 50.85. No money moved.',
      Icons.credit_card,
    ),
    (
      'Contractor payout',
      'Preview a CAD 40 transfer to a sample payout account.',
      'Simulate payout request',
      'Demo payout queued · CAD 40. No money moved.',
      Icons.account_balance_wallet_outlined,
    ),
    (
      'Automatic snow removal',
      'Preview a 3-inch snowfall against a 2-inch service threshold.',
      'Simulate snowfall',
      'Threshold reached. Eden would propose snow removal for Maple House.',
      Icons.ac_unit,
    ),
  ];

  @override
  Widget build(BuildContext context) => MarketPage(
    customerTheme: true,
    title: 'Integration previews',
    children: [
      const MarketBanner(
        'Try a sample workflow',
        'These previews use sample data for the client demo.',
        Icons.play_circle_outline,
      ),
      for (final (title, description, action, result, icon) in _flows)
        MarketCard(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(description),
            ),
            OutlinedButton(
              onPressed: () => showCustomerDialog<void>(
                dark: null,
                context: context,
                builder: (_) => _FlowDialog(
                  title: title,
                  action: action,
                  result: result,
                  verify: title == 'Phone verification',
                ),
              ),
              child: Text(action),
            ),
          ],
        ),
    ],
  );
}

class _FlowDialog extends StatefulWidget {
  const _FlowDialog({
    required this.title,
    required this.action,
    required this.result,
    required this.verify,
  });
  final String title;
  final String action;
  final String result;
  final bool verify;

  @override
  State<_FlowDialog> createState() => _FlowDialogState();
}

class _FlowDialogState extends State<_FlowDialog> {
  final _form = GlobalKey<FormState>();
  bool _complete = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: _complete
        ? Text(widget.result)
        : widget.verify
        ? Form(
            key: _form,
            child: TextFormField(
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Verification code',
                helperText: 'Sample code: 123456',
              ),
              validator: (value) =>
                  value == '123456' ? null : 'Enter the sample code',
            ),
          )
        : const Text('Run this step using sample data.'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_complete ? 'Done' : 'Cancel'),
      ),
      if (!_complete)
        FilledButton(
          onPressed: () {
            if (widget.verify && !_form.currentState!.validate()) return;
            setState(() => _complete = true);
          },
          child: Text(widget.action),
        ),
    ],
  );
}
