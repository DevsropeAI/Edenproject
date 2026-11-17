import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import 'features/home/marketplace.dart';
import 'features/home/presentation/screens/demo_settings_screen.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/domain/auth_state.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_dark_theme.dart';
import 'core/router/app_router.dart';

class EdenApp extends ConsumerWidget {
  static final _messenger = GlobalKey<ScaffoldMessengerState>();
  const EdenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref
        .watch(authProvider)
        .maybeWhen(
          authenticated: (user) => user.role == 'customer',
          orElse: () => false,
        );
    if (customer) {
      ref.listen(bookingsProvider, (previous, next) {
        if (previous == null || !ref.read(demoSettingsProvider).notifications)
          return;
        final lastVersions = {
          for (final booking in previous)
            booking.id: booking.customerNotices.lastOrNull?.version ?? 0,
        };
        final updates = [
          for (final booking in next)
            if (lastVersions[booking.id] case final version?)
              for (final notice in booking.customerNotices)
                if (notice.version > version)
                  (booking: booking, notice: notice),
        ]..sort((a, b) => b.notice.at.compareTo(a.notice.at));
        if (updates.firstOrNull case final latest?) {
          _messenger.currentState?.showSnackBar(
            SnackBar(
              content: Text(orderNoticeText(latest.notice.status)),
              action: SnackBarAction(
                label: 'View order',
                onPressed: () => ref
                    .read(appRouterProvider)
                    .push('/bookings/${latest.booking.id}'),
              ),
            ),
          );
        }
      });
    }
    ref.listen(marketplaceFeedbackProvider, (_, message) {
      if (message != null)
        _messenger.currentState?.showSnackBar(SnackBar(content: Text(message)));
    });
    return MaterialApp.router(
      scaffoldMessengerKey: _messenger,
      title: 'Eden',
      theme: AppTheme.lightTheme,
      darkTheme: EdenDarkTheme.data,
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
