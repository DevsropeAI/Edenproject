import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import 'features/home/marketplace.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

class EdenApp extends ConsumerWidget {
  static final _messenger = GlobalKey<ScaffoldMessengerState>();
  const EdenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(marketplaceFeedbackProvider, (_, message) {
      if (message != null)
        _messenger.currentState?.showSnackBar(SnackBar(content: Text(message)));
    });
    return MaterialApp.router(
      scaffoldMessengerKey: _messenger,
      title: 'Eden',
      theme: AppTheme.lightTheme,
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
