import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../../home/presentation/screens/marketplace_screens.dart';
import '../../domain/auth_state.dart';
import '../../providers/auth_provider.dart';

final _phoneVerificationProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final response = await ref.watch(apiClientProvider).get('/auth/options');
  return response.data['phoneVerification'] == true;
});

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
  final _area = TextEditingController();
  final _resetCode = TextEditingController();
  bool _codeRequested = false;
  final _phoneCode = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
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
      _resetCode,
      _phoneCode,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy ||
        ref
            .read(authProvider)
            .maybeWhen(initial: () => true, orElse: () => false) ||
        !_form.currentState!.validate())
      return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    if (_reset) {
      await _resetPassword();
      return;
    }
    final notifier = ref.read(authProvider.notifier);
    if (_login) {
      await notifier.login(_email.text.trim(), _password.text);
    } else {
      await notifier.register({
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'password': _password.text,
        'phone': _phone.text.trim(),
        'phoneCode': _phoneCode.text.trim(),
        'role': _contractor ? 'contractor' : 'customer',
        'area': _area.text.trim(),
        'service': _contractor ? _service : '',
      });
    }
    if (!mounted) return;
    final result = ref.read(authProvider);
    if (!_login &&
        result.maybeWhen(unauthenticated: () => true, orElse: () => false)) {
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

  Future<void> _sendPhoneCode() async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/auth/phone-verification',
            data: {'phone': _phone.text.trim()},
          );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification code sent.')),
        );
    } catch (error) {
      if (mounted) setState(() => _feedback = apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    try {
      final client = ref.read(apiClientProvider);
      if (_codeRequested) {
        await client.post(
          '/auth/password-reset/confirm',
          data: {'code': _resetCode.text.trim(), 'password': _password.text},
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed. Sign in again.')),
        );
        context.go('/login');
      } else {
        await client.post(
          '/auth/password-reset/request',
          data: {'email': _email.text.trim()},
        );
        if (mounted)
          setState(() {
            _codeRequested = true;
            _feedback = 'If the address belongs to an account, check your email for a reset code.';
          });
      }
    } catch (error) {
      if (mounted) setState(() => _feedback = apiError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final restoring = ref
        .watch(authProvider)
        .maybeWhen(initial: () => true, orElse: () => false);
    final verification = !_login && !_reset
        ? ref.watch(_phoneVerificationProvider)
        : null;
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
                      if (!_reset || !_codeRequested)
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
                      if (verification?.value == true) ...[
                        OutlinedButton(
                          onPressed: _busy ? null : _sendPhoneCode,
                          child: const Text('Send SMS code'),
                        ),
                        _field(
                          _phoneCode,
                          'SMS verification code',
                          Icons.sms_outlined,
                          keyboard: TextInputType.number,
                        ),
                      ],
                      if (verification?.hasError == true)
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(_phoneVerificationProvider),
                          child: const Text('Retry loading registration'),
                        ),
                      if (_reset && _codeRequested)
                        _field(_resetCode, 'Reset code', Icons.key_outlined),
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
                      if (!_reset || _codeRequested)
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
                          onPressed:
                              _busy ||
                                  restoring ||
                                  verification?.isLoading == true ||
                                  verification?.hasError == true
                              ? null
                              : _submit,
                          child: _busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _reset
                                      ? (_codeRequested
                                            ? 'Set new password'
                                            : 'Email reset code')
                                      : (_login ? 'Sign in' : 'Create account'),
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
