import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../home/presentation/screens/marketplace_screens.dart';
import '../../domain/auth_state.dart';
import '../../data/repositories/auth_repository.dart';
import '../../providers/auth_provider.dart';

enum AuthMode { login, customer, contractor, reset }

class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, required this.mode});

  final AuthMode mode;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _verificationCode = TextEditingController();
  final _area = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _resetRequested = false;
  String? _feedback;
  String _service = 'Snow removal';

  bool get _login => widget.mode == AuthMode.login;
  bool get _reset => widget.mode == AuthMode.reset;
  bool get _contractor => widget.mode == AuthMode.contractor;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _password,
      _phone,
      _area,
      _verificationCode,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_reset) {
      if (_resetRequested) {
        final changed = ref
            .read(authRepositoryProvider)
            .resetDemoPassword(_email.text.trim(), _password.text);
        if (changed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Demo password updated.')),
          );
          context.go('/login');
        } else {
          setState(
            () => _feedback = 'Register a demo account in this session first.',
          );
        }
        return;
      }
      setState(
        () => _feedback = 'Use the sample reset link below. No email was sent.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _feedback = null;
    });
    final notifier = ref.read(authProvider.notifier);
    if (_login) {
      await notifier.login(_email.text.trim(), _password.text);
    } else {
      await notifier.register(
        _name.text.trim(),
        _email.text.trim(),
        _password.text,
        _contractor ? 'contractor' : 'customer',
      );
    }
    if (!mounted) return;
    final result = ref.read(authProvider);
    if (!_login &&
        result.maybeWhen(unauthenticated: () => true, orElse: () => false)) {
      ref
          .read(registrationDetailsProvider.notifier)
          .save(
            phone: _phone.text.trim(),
            area: _area.text.trim(),
            service: _contractor ? _service : '',
          );
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created. Sign in to continue.')),
      );
      return;
    }
    final user = result.maybeWhen(
      authenticated: (user) => user,
      orElse: () => null,
    );
    if (user != null) {
      context.go(
        user.role == 'contractor' ? '/contractor-home' : '/customer-home',
      );
      return;
    }
    setState(() {
      _busy = false;
      _feedback = result.maybeWhen(
        error: (message) => message,
        orElse: () => 'Please try again.',
      );
    });
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    String? Function(String)? validate,
  }) => TextFormField(
    controller: controller,
    enabled: !_busy,
    keyboardType: keyboard,
    textInputAction: TextInputAction.next,
    validator: (value) {
      final text = value?.trim() ?? '';
      return text.isEmpty
          ? 'Enter ${label.toLowerCase()}'
          : validate?.call(text);
    },
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
  );

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.mode) {
      AuthMode.login => 'Welcome to Eden',
      AuthMode.customer => 'Create a customer account',
      AuthMode.contractor => 'Create a contractor account',
      AuthMode.reset => 'Reset your password',
    };
    final description = switch (widget.mode) {
      AuthMode.login => 'Sign in to book or manage home services.',
      AuthMode.customer => 'Book services and track work at your properties.',
      AuthMode.contractor =>
        'Tell us where you work and which service you offer.',
      AuthMode.reset => 'Enter the email address associated with your account.',
    };
    return MarketPage(
      title: 'Eden',
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MarketBanner(
                  title,
                  description,
                  _contractor ? Icons.handyman_outlined : Icons.eco_outlined,
                ),
                const SizedBox(height: 16),
                Form(
                  key: _form,
                  child: MarketCard(
                    children: [
                      if (!_login && !_reset)
                        _field(_name, 'Full name', Icons.person_outline),
                      _field(
                        _email,
                        'Email address',
                        Icons.mail_outline,
                        keyboard: TextInputType.emailAddress,
                        validate: (value) =>
                            RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch(value)
                            ? null
                            : 'Enter a valid email address',
                      ),
                      if (!_login && !_reset)
                        _field(
                          _phone,
                          'Phone number',
                          Icons.phone_outlined,
                          keyboard: TextInputType.phone,
                          validate: (value) =>
                              value.replaceAll(RegExp(r'\D'), '').length < 7
                              ? 'Enter a valid phone number'
                              : null,
                        ),
                      if (!_login && !_reset)
                        _field(
                          _verificationCode,
                          'Demo verification code (123456)',
                          Icons.sms_outlined,
                          keyboard: TextInputType.number,
                          validate: (value) => value == '123456'
                              ? null
                              : 'Enter the sample code 123456',
                        ),
                      if (_contractor) ...[
                        _field(
                          _area,
                          'Service area',
                          Icons.location_on_outlined,
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _service,
                          decoration: const InputDecoration(
                            labelText: 'Primary service',
                          ),
                          items: [
                            for (final service in [
                              'Snow removal',
                              'Lawn mowing',
                              'House cleaning',
                            ])
                              DropdownMenuItem(
                                value: service,
                                child: Text(service),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) => setState(() => _service = value!),
                        ),
                      ],
                      if (!_reset || _resetRequested)
                        TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _obscure,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (value) =>
                              (value ?? '').trim().length < (_login ? 1 : 8)
                              ? (_login
                                    ? 'Enter your password'
                                    : 'Use at least 8 characters')
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                      if (_login)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () => context.push('/reset-password'),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                      if (_reset && _feedback != null && !_resetRequested)
                        TextButton(
                          onPressed: () => setState(() {
                            _resetRequested = true;
                            _feedback = null;
                          }),
                          child: const Text('Open sample reset link'),
                        ),
                      if (_feedback != null)
                        Text(
                          _feedback!,
                          style: TextStyle(
                            color: _reset
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _login
                                      ? 'Sign in'
                                      : _reset
                                      ? (_resetRequested
                                            ? 'Set demo password'
                                            : 'Request reset link')
                                      : 'Create account',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_login) ...[
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => context.push('/register/customer'),
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('Create customer account'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => context.push('/register/contractor'),
                    icon: const Icon(Icons.handyman_outlined),
                    label: const Text('Create contractor account'),
                  ),
                ] else
                  TextButton(
                    onPressed: _busy ? null : () => context.go('/login'),
                    child: const Text('Back to sign in'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
