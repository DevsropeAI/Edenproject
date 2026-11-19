import 'work_location_editor.dart';

import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_client.dart';
import '../../marketplace.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/auth_state.dart';
import '../../../auth/providers/auth_provider.dart';
import 'marketplace_screens.dart';

Future<Uint8List?> selectDemoImage(BuildContext context) async {
  try {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image == null) return null;
    if (await image.length() > 2 * 1024 * 1024) {
      throw const FormatException('Image too large');
    }
    return await image.readAsBytes();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an image under 2 MB.')),
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

final accountImageProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, kind) async {
      if (ref.watch(activeAccountIdProvider) == null) return null;
      final response = await ref
          .watch(apiClientProvider)
          .get('/account-images/$kind');
      final image = response.data['image'] as String?;
      return image == null ? null : base64Decode(image);
    });

Future<void> _saveImage(WidgetRef ref, String kind, Uint8List? bytes) async {
  await ref
      .read(apiClientProvider)
      .post(
        '/account-images/$kind',
        data: {'image': bytes == null ? null : base64Encode(bytes)},
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
  bool _saving = false;
  Uint8List? _photo;
  bool _photoEdited = false;

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
        customerTheme: true,
        title: 'Edit profile',
        children: [Text('Sign in to edit your profile.')],
      );
    }
    final photo = _photoEdited
        ? _photo
        : ref.watch(accountImageProvider('profile')).value;
    return MarketPage(
      customerTheme: true,
      title: 'Edit profile',
      children: [
        MarketBanner('Personal details', user.email, Icons.badge_outlined),
        Form(
          key: _form,
          child: MarketCard(
            children: [
              if (photo != null) DemoImage(photo),
              OutlinedButton.icon(
                icon: const Icon(Icons.image_outlined),
                label: const Text('Choose profile photo'),
                onPressed: () async {
                  final photo = await selectDemoImage(context);
                  if (photo != null && mounted)
                    setState(() {
                      _photo = photo;
                      _photoEdited = true;
                    });
                },
              ),
              if (photo != null)
                TextButton(
                  onPressed: () => setState(() {
                    _photo = null;
                    _photoEdited = true;
                  }),
                  child: const Text('Remove profile photo'),
                ),
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
              if (user.role == 'contractor') const WorkLocationEditor(),
              FilledButton(
                onPressed: _deleting || _saving
                    ? null
                    : () async {
                        if (!_form.currentState!.validate()) return;
                        setState(() => _saving = true);
                        try {
                          await ref
                              .read(authProvider.notifier)
                              .updateProfile(
                                user.copyWith(name: _name.text.trim()),
                                _phone.text.trim(),
                              );
                          if (!mounted) return;
                          if (_photoEdited) {
                            await _saveImage(ref, 'profile', _photo);
                            if (!mounted) return;
                            ref.invalidate(accountImageProvider('profile'));
                          }
                          if (context.mounted) context.pop();
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(apiError(error))),
                          );
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                child: const Text('Save changes'),
              ),
            ],
          ),
        ),
        MarketCard(
          children: [
            TextButton(
              onPressed: _deleting || _saving
                  ? null
                  : () async {
                      final confirm = await showCustomerDialog<bool>(
                        dark: null,
                        context: context,
                        builder: (dialog) => AlertDialog(
                          title: const Text('Delete account?'),
                          content: const Text(
                            'This deletes your account and support requests.',
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
                        await ref.read(authProvider.notifier).deleteAccount();
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
                'Delete account',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final contractorVerificationProvider = FutureProvider.autoDispose<String>((
  ref,
) async {
  if (ref.watch(activeAccountIdProvider) == null) return 'Incomplete';
  final response = await ref
      .watch(apiClientProvider)
      .get('/contractor/verification');
  return response.data['status'] as String;
});

class VerificationScreen extends ConsumerWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verification = ref.watch(contractorVerificationProvider);
    return MarketPage(
      title: 'Verification documents',
      dark: true,
      children: [
        const MarketBanner(
          'Verification documents',
          'Upload your ID and insurance. Eden reviews both documents before you can accept jobs.',
          Icons.verified_user_outlined,
        ),
        MarketCard(
          children: [
            Text(
              verification.when(
                data: (status) => switch (status) {
                  'Approved' => 'Approved. You can accept jobs.',
                  'Rejected' =>
                    'Documents need changes. Upload replacements for review.',
                  'Pending' =>
                    'Both documents uploaded. Waiting for admin approval.',
                  _ => 'Upload both documents to get verified.',
                },
                loading: () => 'Checking verification status…',
                error: (_, _) => 'Could not check verification status.',
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(contractorVerificationProvider),
              child: const Text('Refresh status'),
            ),
          ],
        ),
        for (final (kind, label) in [
          ('identification', 'Identification'),
          ('insurance', 'Insurance'),
        ])
          MarketCard(
            children: [
              Text(label, style: Theme.of(context).textTheme.titleLarge),
              if (ref.watch(accountImageProvider(kind)).value case final bytes?)
                DemoImage(bytes),
              OutlinedButton.icon(
                icon: const Icon(Icons.attach_file),
                label: const Text('Upload image'),
                onPressed: () async {
                  final bytes = await selectDemoImage(context);
                  if (bytes != null && context.mounted) {
                    try {
                      await _saveImage(ref, kind, bytes);
                      if (context.mounted) {
                        ref.invalidate(accountImageProvider(kind));
                        ref.invalidate(contractorVerificationProvider);
                      }
                    } catch (error) {
                      if (context.mounted)
                        ref
                            .read(marketplaceFeedbackProvider.notifier)
                            .report(error);
                    }
                  }
                },
              ),
            ],
          ),
      ],
    );
  }
}

// import 'dart:typed_data';
// import 'dart:convert';

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:image_picker/image_picker.dart';

// import '../../../../core/network/api_client.dart';
// import '../../marketplace.dart';
// import '../../../auth/data/repositories/auth_repository.dart';
// import '../../../auth/domain/auth_state.dart';
// import '../../../auth/providers/auth_provider.dart';
// import 'marketplace_screens.dart';

// Future<Uint8List?> selectDemoImage(BuildContext context) async {
//   try {
//     final image = await ImagePicker().pickImage(
//       source: ImageSource.gallery,
//       maxWidth: 1600,
//       imageQuality: 85,
//     );
//     if (image == null) return null;
//     if (await image.length() > 2 * 1024 * 1024) {
//       throw const FormatException('Image too large');
//     }
//     return await image.readAsBytes();
//   } catch (_) {
//     if (context.mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Choose an image under 2 MB.')),
//       );
//     }
//     return null;
//   }
// }

// class DemoImage extends StatelessWidget {
//   const DemoImage(this.bytes, {super.key});
//   final Uint8List bytes;

//   @override
//   Widget build(BuildContext context) => ClipRRect(
//     borderRadius: BorderRadius.circular(12),
//     child: Image.memory(
//       bytes,
//       width: double.infinity,
//       height: 160,
//       fit: BoxFit.cover,
//       errorBuilder: (_, _, _) => const Text('Image preview unavailable'),
//     ),
//   );
// }

// final accountImageProvider = FutureProvider.autoDispose
//     .family<Uint8List?, String>((ref, kind) async {
//       if (ref.watch(activeAccountIdProvider) == null) return null;
//       final response = await ref
//           .watch(apiClientProvider)
//           .get('/account-images/$kind');
//       final image = response.data['image'] as String?;
//       return image == null ? null : base64Decode(image);
//     });

// Future<void> _saveImage(WidgetRef ref, String kind, Uint8List? bytes) async {
//   await ref
//       .read(apiClientProvider)
//       .post(
//         '/account-images/$kind',
//         data: {'image': bytes == null ? null : base64Encode(bytes)},
//       );
// }

// class EditProfileScreen extends ConsumerStatefulWidget {
//   const EditProfileScreen({super.key});

//   @override
//   ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
// }

// class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
//   final _form = GlobalKey<FormState>();
//   late final _name = TextEditingController(
//     text: ref
//         .read(authProvider)
//         .maybeWhen(authenticated: (user) => user.name, orElse: () => ''),
//   );
//   late final _phone = TextEditingController(
//     text: ref.read(registrationDetailsProvider).phone,
//   );
//   bool _deleting = false;
//   bool _saving = false;
//   Uint8List? _photo;
//   bool _photoEdited = false;

//   @override
//   void dispose() {
//     _name.dispose();
//     _phone.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final user = ref
//         .watch(authProvider)
//         .maybeWhen(authenticated: (user) => user, orElse: () => null);
//     if (user == null) {
//       return const MarketPage(
//         customerTheme: true,
//         title: 'Edit profile',
//         children: [Text('Sign in to edit your profile.')],
//       );
//     }
//     final photo = _photoEdited
//         ? _photo
//         : ref.watch(accountImageProvider('profile')).value;
//     return MarketPage(
//       customerTheme: true,
//       title: 'Edit profile',
//       children: [
//         MarketBanner('Personal details', user.email, Icons.badge_outlined),
//         Form(
//           key: _form,
//           child: MarketCard(
//             children: [
//               if (photo != null) DemoImage(photo),
//               OutlinedButton.icon(
//                 icon: const Icon(Icons.image_outlined),
//                 label: const Text('Choose profile photo'),
//                 onPressed: () async {
//                   final photo = await selectDemoImage(context);
//                   if (photo != null && mounted)
//                     setState(() {
//                       _photo = photo;
//                       _photoEdited = true;
//                     });
//                 },
//               ),
//               if (photo != null)
//                 TextButton(
//                   onPressed: () => setState(() {
//                     _photo = null;
//                     _photoEdited = true;
//                   }),
//                   child: const Text('Remove profile photo'),
//                 ),
//               TextFormField(
//                 controller: _name,
//                 decoration: const InputDecoration(labelText: 'Full name'),
//                 validator: (value) =>
//                     (value ?? '').trim().isEmpty ? 'Enter your name' : null,
//               ),
//               TextFormField(
//                 controller: _phone,
//                 keyboardType: TextInputType.phone,
//                 decoration: const InputDecoration(labelText: 'Phone number'),
//                 validator: (value) {
//                   final phone = (value ?? '').trim();
//                   return phone.isNotEmpty &&
//                           phone.replaceAll(RegExp(r'\D'), '').length < 7
//                       ? 'Enter a valid phone number'
//                       : null;
//                 },
//               ),
//               FilledButton(
//                 onPressed: _deleting || _saving
//                     ? null
//                     : () async {
//                         if (!_form.currentState!.validate()) return;
//                         setState(() => _saving = true);
//                         try {
//                           await ref
//                               .read(authProvider.notifier)
//                               .updateProfile(
//                                 user.copyWith(name: _name.text.trim()),
//                                 _phone.text.trim(),
//                               );
//                           if (!mounted) return;
//                           if (_photoEdited) {
//                             await _saveImage(ref, 'profile', _photo);
//                             if (!mounted) return;
//                             ref.invalidate(accountImageProvider('profile'));
//                           }
//                           if (context.mounted) context.pop();
//                         } catch (error) {
//                           if (!context.mounted) return;
//                           ScaffoldMessenger.of(context).showSnackBar(
//                             SnackBar(content: Text(apiError(error))),
//                           );
//                         } finally {
//                           if (mounted) setState(() => _saving = false);
//                         }
//                       },
//                 child: const Text('Save changes'),
//               ),
//             ],
//           ),
//         ),
//         MarketCard(
//           children: [
//             TextButton(
//               onPressed: _deleting || _saving
//                   ? null
//                   : () async {
//                       final confirm = await showCustomerDialog<bool>(
//                         dark: null,
//                         context: context,
//                         builder: (dialog) => AlertDialog(
//                           title: const Text('Delete account?'),
//                           content: const Text(
//                             'This deletes your account and support requests.',
//                           ),
//                           actions: [
//                             TextButton(
//                               onPressed: () => Navigator.pop(dialog, false),
//                               child: const Text('Cancel'),
//                             ),
//                             FilledButton(
//                               onPressed: () => Navigator.pop(dialog, true),
//                               child: const Text('Delete account'),
//                             ),
//                           ],
//                         ),
//                       );
//                       if (!mounted || confirm != true) return;
//                       setState(() => _deleting = true);
//                       try {
//                         await ref.read(authProvider.notifier).deleteAccount();
//                       } catch (_) {
//                         if (!context.mounted) return;
//                         setState(() => _deleting = false);
//                         ScaffoldMessenger.of(context).showSnackBar(
//                           const SnackBar(
//                             content: Text('Account could not be deleted.'),
//                           ),
//                         );
//                       }
//                     },
//               child: Text(
//                 'Delete account',
//                 style: TextStyle(color: Theme.of(context).colorScheme.error),
//               ),
//             ),
//           ],
//         ),
//       ],
//     );
//   }
// }

// final contractorVerificationProvider = FutureProvider.autoDispose<String>((
//   ref,
// ) async {
//   if (ref.watch(activeAccountIdProvider) == null) return 'Incomplete';
//   final response = await ref
//       .watch(apiClientProvider)
//       .get('/contractor/verification');
//   return response.data['status'] as String;
// });

// class VerificationScreen extends ConsumerWidget {
//   const VerificationScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final verification = ref.watch(contractorVerificationProvider);
//     return MarketPage(
//       title: 'Verification documents',
//       children: [
//         const MarketBanner(
//           'Verification documents',
//           'Upload your ID and insurance. Eden reviews both documents before you can accept jobs.',
//           Icons.verified_user_outlined,
//         ),
//         MarketCard(
//           children: [
//             Text(
//               verification.when(
//                 data: (status) => switch (status) {
//                   'Approved' => 'Approved. You can accept jobs.',
//                   'Rejected' =>
//                     'Documents need changes. Upload replacements for review.',
//                   'Pending' =>
//                     'Both documents uploaded. Waiting for admin approval.',
//                   _ => 'Upload both documents to get verified.',
//                 },
//                 loading: () => 'Checking verification status…',
//                 error: (_, _) => 'Could not check verification status.',
//               ),
//             ),
//             TextButton(
//               onPressed: () => ref.invalidate(contractorVerificationProvider),
//               child: const Text('Refresh status'),
//             ),
//           ],
//         ),
//         for (final (kind, label) in [
//           ('identification', 'Identification'),
//           ('insurance', 'Insurance'),
//         ])
//           MarketCard(
//             children: [
//               Text(label, style: Theme.of(context).textTheme.titleLarge),
//               if (ref.watch(accountImageProvider(kind)).value case final bytes?)
//                 DemoImage(bytes),
//               OutlinedButton.icon(
//                 icon: const Icon(Icons.attach_file),
//                 label: const Text('Upload image'),
//                 onPressed: () async {
//                   final bytes = await selectDemoImage(context);
//                   if (bytes != null && context.mounted) {
//                     try {
//                       await _saveImage(ref, kind, bytes);
//                       if (context.mounted) {
//                         ref.invalidate(accountImageProvider(kind));
//                         ref.invalidate(contractorVerificationProvider);
//                       }
//                     } catch (error) {
//                       if (context.mounted)
//                         ref
//                             .read(marketplaceFeedbackProvider.notifier)
//                             .report(error);
//                     }
//                   }
//                 },
//               ),
//             ],
//           ),
//       ],
//     );
//   }
// }
