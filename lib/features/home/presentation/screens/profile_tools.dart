import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../auth/domain/auth_state.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../marketplace.dart';
import 'demo_settings_screen.dart';
import 'marketplace_screens.dart';

Future<Uint8List?> selectDemoImage(BuildContext context) async {
  try {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image == null) return null;
    if (await image.length() > 10 * 1024 * 1024) {
      throw const FormatException('Image too large');
    }
    return await image.readAsBytes();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an image under 10 MB.')),
      );
    }
    return null;
  }
}

class DemoImage extends StatelessWidget {
  const DemoImage(this.bytes, {super.key});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.memory(
      bytes,
      width: double.infinity,
      height: 160,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const Text('Image preview unavailable'),
    ),
  );
}

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: ref
        .read(authProvider)
        .maybeWhen(authenticated: (user) => user.name, orElse: () => ''),
  );
  late final _phone = TextEditingController(
    text: ref.read(registrationDetailsProvider).phone,
  );
  bool _deleting = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref
        .watch(authProvider)
        .maybeWhen(authenticated: (user) => user, orElse: () => null);
    if (user == null) {
      return const MarketPage(
        title: 'Edit profile',
        children: [Text('Sign in to edit your profile.')],
      );
    }
    return MarketPage(
      title: 'Edit profile',
      children: [
        MarketBanner('Personal details', user.email, Icons.badge_outlined),
        Form(
          key: _form,
          child: MarketCard(
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter your name' : null,
              ),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
                validator: (value) {
                  final phone = (value ?? '').trim();
                  return phone.isNotEmpty &&
                          phone.replaceAll(RegExp(r'\D'), '').length < 7
                      ? 'Enter a valid phone number'
                      : null;
                },
              ),
              FilledButton(
                onPressed: _deleting
                    ? null
                    : () {
                        if (!_form.currentState!.validate()) return;
                        final details = ref.read(registrationDetailsProvider);
                        ref
                            .read(registrationDetailsProvider.notifier)
                            .save(
                              phone: _phone.text.trim(),
                              area: details.area,
                              service: details.service,
                            );
                        ref
                            .read(authProvider.notifier)
                            .updateProfile(
                              user.copyWith(name: _name.text.trim()),
                            );
                        context.pop();
                      },
                child: const Text('Save changes'),
              ),
            ],
          ),
        ),
        MarketCard(
          children: [
            TextButton(
              onPressed: _deleting
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dialog) => AlertDialog(
                          title: const Text('Delete demo account?'),
                          content: const Text(
                            'This clears your account and marketplace changes from this session.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialog, true),
                              child: const Text('Delete account'),
                            ),
                          ],
                        ),
                      );
                      if (!mounted || confirm != true) return;
                      setState(() => _deleting = true);
                      try {
                        await ref
                            .read(authProvider.notifier)
                            .deleteAccount(user.email);
                        if (!context.mounted) return;
                        ref.invalidate(registrationDetailsProvider);
                        ref.invalidate(propertiesProvider);
                        ref.invalidate(bookingsProvider);
                        ref.invalidate(demoSettingsProvider);
                        ref.invalidate(payoutRequestedProvider);
                        ref.invalidate(verificationProvider);
                        context.go('/login');
                      } catch (_) {
                        if (!context.mounted) return;
                        setState(() => _deleting = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Account could not be deleted.'),
                          ),
                        );
                      }
                    },
              child: Text(
                'Delete demo account',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final verificationProvider =
    NotifierProvider<Verification, Map<String, Uint8List>>(Verification.new);

class Verification extends Notifier<Map<String, Uint8List>> {
  @override
  Map<String, Uint8List> build() => const {};

  void attach(String kind, Uint8List bytes) => state = {...state, kind: bytes};
}

class VerificationScreen extends ConsumerWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(verificationProvider);
    return MarketPage(
      title: 'Verification documents',
      children: [
        const MarketBanner(
          'Verification documents',
          'Use sample images in this demo. Files are held in this session.',
          Icons.verified_user_outlined,
        ),
        for (final kind in ['Identification', 'Insurance'])
          MarketCard(
            children: [
              Text(kind, style: Theme.of(context).textTheme.titleLarge),
              if (files[kind] case final bytes?) DemoImage(bytes),
              OutlinedButton.icon(
                icon: const Icon(Icons.attach_file),
                label: Text(
                  files.containsKey(kind)
                      ? 'Replace sample image'
                      : 'Choose sample image',
                ),
                onPressed: () async {
                  final bytes = await selectDemoImage(context);
                  if (bytes != null && context.mounted) {
                    ref.read(verificationProvider.notifier).attach(kind, bytes);
                  }
                },
              ),
            ],
          ),
      ],
    );
  }
}
