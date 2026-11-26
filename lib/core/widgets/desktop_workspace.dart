import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

abstract final class EdenDesktopLayout {
  static const breakpoint = 1100.0;
  static const sidebarWidth = 232.0;
  static const actionWidth = 220.0;
  static const contentWidth = 1360.0;
  static const formWidth = 1040.0;
  static bool forWidth(double width, {bool web = kIsWeb}) =>
      web && width >= breakpoint;
  static bool enabled(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);
}

class EdenDesktopGrid extends StatelessWidget {
  const EdenDesktopGrid({
    super.key,
    required this.children,
    this.minimumWidth = 340,
    this.maximumColumns = 3,
  });
  final List<Widget> children;
  final double minimumWidth;
  final int maximumColumns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          ((constraints.maxWidth + EdenSpacing.section) /
                  (minimumWidth + EdenSpacing.section))
              .floor()
              .clamp(1, maximumColumns);
      final width =
          (constraints.maxWidth - EdenSpacing.section * (columns - 1)) /
          columns;
      return Wrap(
        spacing: EdenSpacing.section,
        runSpacing: EdenSpacing.section,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class EdenDesktopWorkspace extends StatelessWidget {
  const EdenDesktopWorkspace({
    super.key,
    required this.title,
    required this.role,
    required this.currentPath,
    required this.onNavigate,
    required this.children,
    this.name = '',
    this.actions = const [],
    this.onBack,
    this.maxWidth = EdenDesktopLayout.contentWidth,
  });
  final String title;
  final String role;
  final String name;
  final String currentPath;
  final ValueChanged<String> onNavigate;
  final List<Widget> children;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final double maxWidth;

  bool _selected(String path) {
    if (currentPath == path) return true;
    if (path == '/bookings') return currentPath.startsWith('/bookings/');
    if (path == '/explore-services') return currentPath.startsWith('/booking/');
    if (path == '/contractor-home') {
      return currentPath.startsWith('/job-details/');
    }
    if (path == '/settings/support') return currentPath.startsWith('/chat/');
    if (path == '/profile') {
      return currentPath.startsWith('/profile/') ||
          currentPath.startsWith('/account/') ||
          currentPath == '/verification' ||
          (currentPath.startsWith('/settings/') &&
              !['/settings/support', '/settings/wallet'].contains(currentPath));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final contractor = role == 'contractor';
    final workspace = contractor
        ? 'Contractor workspace'
        : 'Customer workspace';
    final text = Theme.of(context).textTheme;
    final destinations = contractor
        ? [
            (Icons.work_outline, 'Jobs', '/contractor-home'),
            (
              Icons.account_balance_wallet_outlined,
              'Earnings',
              '/settings/wallet',
            ),
            (
              Icons.support_agent_outlined,
              'Support & messages',
              '/settings/support',
            ),
            (Icons.person_outline, 'Profile & settings', '/profile'),
          ]
        : [
            (Icons.space_dashboard_outlined, 'Overview', '/customer-home'),
            (Icons.receipt_long_outlined, 'Orders', '/bookings'),
            (Icons.grid_view_rounded, 'Explore services', '/explore-services'),
            (Icons.home_work_outlined, 'Properties', '/properties'),
            (
              Icons.support_agent_outlined,
              'Support & messages',
              '/settings/support',
            ),
            (Icons.person_outline, 'Profile & settings', '/profile'),
          ];
    final sidebar = Container(
      width: EdenDesktopLayout.sidebarWidth,
      decoration: const BoxDecoration(
        color: EdenDarkColors.surface,
        border: Border(right: BorderSide(color: EdenDarkColors.outline)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(EdenSpacing.section),
              child: Row(
                children: [
                  const Icon(
                    Icons.home_work_rounded,
                    color: EdenDarkColors.accent,
                    size: EdenSpacing.large,
                  ),
                  const SizedBox(width: EdenSpacing.gap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('EDEN', style: text.headlineMedium),
                        Text(
                          contractor ? 'For contractors' : 'For your home',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(EdenSpacing.screen),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(EdenSpacing.sm),
                    child: Text(
                      'WORKSPACE',
                      style: text.labelSmall?.copyWith(
                        color: EdenDarkColors.secondary,
                      ),
                    ),
                  ),
                  for (final (icon, label, path) in destinations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: EdenSpacing.sm),
                      child: Material(
                        color: _selected(path)
                            ? EdenDarkColors.accent.withValues(alpha: .14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(EdenRadius.field),
                        child: ListTile(
                          selected: _selected(path),
                          selectedColor: EdenDarkColors.accent,
                          minTileHeight: EdenSpacing.control,
                          leading: Icon(icon),
                          title: Text(
                            label,
                            style: text.bodyMedium?.copyWith(
                              color: _selected(path)
                                  ? EdenDarkColors.accent
                                  : EdenDarkColors.text,
                            ),
                          ),
                          onTap: () => onNavigate(path),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(EdenSpacing.screen),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: EdenDarkColors.strongGlass,
                  child: Icon(Icons.person_outline, color: EdenDarkColors.text),
                ),
                title: Text(
                  name.isEmpty ? 'Your account' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  contractor ? 'Contractor account' : 'Customer account',
                ),
                onTap: () => onNavigate('/profile'),
              ),
            ),
          ],
        ),
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: EdenSpacing.large,
            vertical: EdenSpacing.screen,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: EdenDarkColors.outline)),
          ),
          child: Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  onPressed: onBack,
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: EdenSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(workspace, style: text.bodySmall),
                    Text(title, style: text.titleLarge),
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: EdenSpacing.sm,
                    children: actions,
                  ),
                ),
              const SizedBox(width: EdenSpacing.screen),
              IconButton(
                onPressed: () => onNavigate('/settings/preferences'),
                tooltip: 'Notification settings',
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              IconButton(
                onPressed: () => onNavigate('/profile'),
                tooltip: 'Profile',
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ListView(
                padding: const EdgeInsets.all(EdenSpacing.large),
                children: [
                  for (final child in children)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: EdenSpacing.section,
                      ),
                      child: child,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      key: const Key('desktop-workspace'),
      backgroundColor: EdenDarkColors.background,
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sidebar,
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}
