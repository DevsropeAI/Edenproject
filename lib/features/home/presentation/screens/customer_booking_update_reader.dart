import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

import '../../marketplace.dart';

class CustomerBookingUpdateBadge extends StatelessWidget {
  const CustomerBookingUpdateBadge({
    super.key,
    this.label = 'New booking update',
  });
  final String label;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      label: label,
      child: const Icon(
        Icons.notifications_active_outlined,
        size: EdenSpacing.screen,
        color: EdenDarkColors.accent,
      ),
    ),
  );
}

/// Acknowledges only progress updates actually displayed on the current route.
/// Chat messages retain their independent read positions.
class CustomerBookingUpdateReader extends ConsumerStatefulWidget {
  const CustomerBookingUpdateReader({
    super.key,
    required this.booking,
    required this.child,
    this.enabled = true,
  });
  final Booking booking;
  final Widget child;
  final bool enabled;
  @override
  ConsumerState<CustomerBookingUpdateReader> createState() =>
      _CustomerBookingUpdateReaderState();
}

class _CustomerBookingUpdateReaderState
    extends ConsumerState<CustomerBookingUpdateReader>
    with WidgetsBindingObserver {
  bool _visible = true;
  bool _reading = false;
  int _confirmed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _visible =
        state == null ||
        state == AppLifecycleState.resumed ||
        (kIsWeb && state == AppLifecycleState.inactive);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(
        () => _visible =
            state == AppLifecycleState.resumed ||
            (kIsWeb && state == AppLifecycleState.inactive),
      );
    }
  }

  @override
  void didUpdateWidget(covariant CustomerBookingUpdateReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.booking.id != widget.booking.id) _confirmed = 0;
  }

  Future<void> _read() async {
    final booking = widget.booking;
    final version = booking.latestCustomerNoticeVersion;
    if (!mounted ||
        !widget.enabled ||
        !_visible ||
        _reading ||
        ModalRoute.of(context)?.isCurrent != true ||
        !booking.hasUnreadUpdates ||
        version <= _confirmed) {
      return;
    }
    _reading = true;
    var success = false;
    try {
      await ref
          .read(bookingsProvider.notifier)
          .markUpdatesRead(booking.id, version);
      if (mounted && widget.booking.id == booking.id) _confirmed = version;
      success = true;
    } catch (_) {
      // Preserve the badge; an ordinary booking refresh retries without hiding errors as reads.
    } finally {
      _reading = false;
      if (mounted &&
          success &&
          widget.booking.hasUnreadUpdates &&
          (widget.booking.id != booking.id ||
              widget.booking.latestCustomerNoticeVersion > version)) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _read();
    });
    return widget.child;
  }
}
