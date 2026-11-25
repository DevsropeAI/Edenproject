import '../../../../core/theme/app_dark_theme.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_background.dart';
import '../../../../core/widgets/glass_controls.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../../home/presentation/screens/marketplace_screens.dart';
import '../../../home/presentation/screens/work_location_pin_field.dart';
import '../../domain/auth_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/account_options_provider.dart';
import '../../../home/marketplace.dart' show serviceDetailsProvider;
import 'registration_services_picker.dart';

final _phoneVerificationProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final options = await ref.watch(accountOptionsProvider.future);
  return options['phoneVerification'] == true;
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
  Set<String> _additionalServiceIds = {};
  static const _legacyServices = <Map<String, dynamic>>[
    {'id': 'snow', 'title': 'Snow removal'},
    {'id': 'lawn', 'title': 'Lawn mowing'},
    {'id': 'cleaning', 'title': 'House cleaning'},
  ];
  WorkPin? _workPin;

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
    if (_contractor && ref.read(accountOptionsProvider).asData?.value['contractorWorkPin'] != true) {
      setState(() => _feedback = 'Work-location pins require the updated backend. Restart it and reload registration.');
      ref.invalidate(accountOptionsProvider);
      return;
    }
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
        'area': _workPin != null ? 'Pinned work location' : _area.text.trim(),
        'service': _contractor ? registrationPrimaryTitle(ref.read(serviceDetailsProvider).asData?.value ?? _legacyServices, _service) : '',
        if (_contractor) 'serviceIds': _additionalServiceIds.toList(),
        if (_contractor && _workPin != null) 'workPin': {'latitude':_workPin!.latitude,'longitude':_workPin!.longitude},
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

  Widget _buildLogin(bool restoring) => Theme(
    data: EdenDarkTheme.data,
    child: Scaffold(
      body: AppBackground(
        showRibbon: true,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(EdenSpacing.screen),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - EdenSpacing.large).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: EdenSpacing.content,
                    ),
                    child: Builder(
                      builder: (context) {
                        final theme = Theme.of(context);
                        final reducedMotion = MediaQuery.disableAnimationsOf(
                          context,
                        );
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) => Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, (1 - value) * EdenSpacing.gap),
                              child: child,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: GlassCard(
                                  blur: true,
                                  child: Icon(
                                    Icons.home_work_outlined,
                                    semanticLabel: 'Eden',
                                  ),
                                ),
                              ),
                              const SizedBox(height: EdenSpacing.section),
                              Text(
                                'Welcome to Eden',
                                style: theme.textTheme.headlineLarge,
                              ),
                              const SizedBox(height: EdenSpacing.sm),
                              Text(
                                'Sign in to book or manage home services.',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: EdenSpacing.section),
                              GlassCard(
                                solid: true,
                                child: Form(
                                  key: _form,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _field(
                                        _email,
                                        'Email address',
                                        Icons.mail_outline,
                                        keyboard: TextInputType.emailAddress,
                                        validate: (value) =>
                                            RegExp(
                                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                            ).hasMatch(value)
                                            ? null
                                            : 'Enter a valid email address',
                                      ),
                                      const SizedBox(height: EdenSpacing.gap),
                                      GlassTextField(
                                        controller: _password,
                                        enabled: !_busy,
                                        obscureText: _obscure,
                                        onSubmitted: (_) => _submit(),
                                        validator: (value) =>
                                            (value ?? '').trim().isEmpty
                                            ? 'Enter your password'
                                            : null,
                                        decoration: InputDecoration(
                                          labelText: 'Password',
                                          prefixIcon: const Icon(
                                            Icons.lock_outline,
                                          ),
                                          suffixIcon: IconButton(
                                            tooltip: _obscure
                                                ? 'Show password'
                                                : 'Hide password',
                                            icon: Icon(
                                              _obscure
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscure = !_obscure,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => context.push(
                                                  '/reset-password',
                                                ),
                                          child: const Text('Forgot password?'),
                                        ),
                                      ),
                                      if (_feedback case final feedback?)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: EdenSpacing.gap,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.error_outline,
                                                color: theme.colorScheme.error,
                                              ),
                                              const SizedBox(
                                                width: EdenSpacing.sm,
                                              ),
                                              Expanded(
                                                child: Text(
                                                  feedback,
                                                  style: TextStyle(
                                                    color:
                                                        theme.colorScheme.error,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      PrimaryButton(
                                        onPressed: _busy || restoring
                                            ? null
                                            : _submit,
                                        child: _busy || restoring
                                            ? const SizedBox.square(
                                                dimension: EdenSpacing.section,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      semanticsLabel:
                                                          'Loading sign-in',
                                                    ),
                                              )
                                            : const Text('Sign in'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: EdenSpacing.section),
                              SecondaryButton(
                                onPressed: _busy
                                    ? null
                                    : () => context.push('/register/customer'),
                                icon: Icons.home_outlined,
                                label: 'Create customer account',
                              ),
                              const SizedBox(height: EdenSpacing.screen),
                              SecondaryButton(
                                onPressed: _busy
                                    ? null
                                    : () =>
                                          context.push('/register/contractor'),
                                icon: Icons.handyman_outlined,
                                label: 'Create contractor account',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final restoring = ref
        .watch(authProvider)
        .maybeWhen(initial: () => true, orElse: () => false);
    if (_login) return _buildLogin(restoring);
    final verification = !_login && !_reset
        ? ref.watch(_phoneVerificationProvider)
        : null;
    final catalog = _contractor ? ref.watch(serviceDetailsProvider) : null;
    final accountOptions = _contractor ? ref.watch(accountOptionsProvider) : null;
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
        'Tell us where you work and which services you offer.',
      AuthMode.reset => 'Enter the email address associated with your account.',
    };
    return MarketPage(
      title: 'Eden',
      dark: !_reset,
      showRibbon: !_reset,
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
                    solid: true,
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
                        WorkLocationPinField(value:_workPin,required:true,enabled:!_busy,onChanged:(pin)=>setState(()=>_workPin=pin)),
                        if (catalog?.isLoading == true) const LinearProgressIndicator(),
                        if (catalog?.hasError == true) TextButton(
                          onPressed: () => ref.invalidate(serviceDetailsProvider),
                          child: const Text('Retry loading all services'),
                        ),
                        RegistrationServicesPicker(
                          services: catalog?.asData?.value ?? _legacyServices,
                          primary: _service, additionalIds: _additionalServiceIds,
                          enabled: !_busy,
                          supportsAdditional: accountOptions?.asData?.value['contractorRegistrationServices'] == true,
                          onPrimaryChanged: (value) => setState(() {
                            _service = value;
                            final id = (catalog?.asData?.value ?? _legacyServices).where((service) => service['title'] == value).firstOrNull?['id'];
                            _additionalServiceIds.remove(id);
                          }),
                          onAdditionalChanged: (ids) => setState(() => _additionalServiceIds = ids),
                        ),
                        if (accountOptions?.hasError == true ||
                            (accountOptions?.hasValue == true && accountOptions?.asData?.value['contractorRegistrationServices'] != true))
                          TextButton(
                            onPressed: () { ref.invalidate(accountOptionsProvider); ref.invalidate(serviceDetailsProvider); },
                            child: const Text('Refresh service options'),
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
