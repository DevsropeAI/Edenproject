import 'marketplace_screens.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../marketplace.dart';

class ModeSwitchTile extends ConsumerStatefulWidget {
  const ModeSwitchTile({
    super.key,
    required this.contractor,
    required this.area,
  });

  final bool contractor;
  final String area;

  @override
  ConsumerState<ModeSwitchTile> createState() => _ModeSwitchTileState();
}

class _ModeSwitchTileState extends ConsumerState<ModeSwitchTile> {
  bool _busy = false;

  Future<void> _switch() async {
    setState(() => _busy = true);
    final role = widget.contractor ? 'customer' : 'contractor';
    try {
      final details = role == 'contractor' && widget.area.isEmpty
          ? await showCustomerDialog<({String area, String service})>(
              context: context,
              dark: null,
              builder: (_) => const _ContractorSetup(),
            )
          : (area: '', service: '');
      if (!mounted || details == null) return;
      await ref
          .read(authProvider.notifier)
          .switchMode(role, area: details.area, service: details.service);
      if (mounted) context.go('/$role-home');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.swap_horiz),
    title: Text(
      widget.contractor ? 'Switch to customer' : 'Switch to contractor',
    ),
    onTap: _busy ? null : _switch,
  );
}

class _ContractorSetup extends StatefulWidget {
  const _ContractorSetup();

  @override
  State<_ContractorSetup> createState() => _ContractorSetupState();
}

class _ContractorSetupState extends State<_ContractorSetup> {
  final _form = GlobalKey<FormState>();
  final _area = TextEditingController();
  String _service = 'Snow removal';

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set up contractor mode'),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _area,
            maxLength: 150,
            decoration: const InputDecoration(labelText: 'Service area'),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Enter your service area' : null,
          ),
          DropdownButtonFormField<String>(
            initialValue: _service,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Primary service'),
            items: [
              for (final service in Service.values)
                DropdownMenuItem(
                  value:
                      service.label[0] +
                      service.label.substring(1).toLowerCase(),
                  child: Text(service.label),
                ),
            ],
            onChanged: (value) => setState(() => _service = value!),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, (
              area: _area.text.trim(),
              service: _service,
            ));
          }
        },
        child: const Text('Switch mode'),
      ),
    ],
  );
}
