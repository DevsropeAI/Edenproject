import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.blur = false,
    this.solid = false,
  });
  final Widget child;
  final bool blur;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(EdenRadius.card);
    final surface = Ink(
      decoration: BoxDecoration(
        color: solid ? EdenDarkColors.surface : null,
        gradient: solid
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [EdenDarkColors.glassTop, EdenDarkColors.glassBottom],
              ),
        border: Border.all(color: EdenDarkColors.strongGlass),
        borderRadius: radius,
      ),
      child: Padding(
        padding: const EdgeInsets.all(EdenSpacing.section),
        child: child,
      ),
    );
    final material = Material(type: MaterialType.transparency, child: surface);
    return ClipRRect(
      borderRadius: radius,
      child: blur && !solid
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: material,
            )
          : material,
    );
  }
}

class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
  });
  final VoidCallback? onPressed;
  final Widget child;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.onPressed == null
        ? null
        : (_) => setState(() => _pressed = true),
    onPointerUp: (_) => setState(() => _pressed = false),
    onPointerCancel: (_) => setState(() => _pressed = false),
    child: AnimatedScale(
      scale: _pressed ? .97 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 110),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          shadows: widget.onPressed == null
              ? null
              : [
                  BoxShadow(
                    color: EdenDarkColors.accent.withValues(alpha: .2),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: FilledButton(
          onPressed: widget.onPressed == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  widget.onPressed!();
                },
          child: widget.child,
        ),
      ),
    ),
  );
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.icon,
  });
  final VoidCallback? onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label, textAlign: TextAlign.center),
  );
}

class GlassTextField extends StatelessWidget {
  const GlassTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.validator,
    this.enabled = true,
    this.obscureText = false,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    decoration: decoration,
    validator: validator,
    enabled: enabled,
    obscureText: obscureText,
    onFieldSubmitted: onSubmitted,
    errorBuilder: (context, error) => Row(
      children: [
        const Icon(
          Icons.error_outline,
          color: EdenDarkColors.error,
          size: EdenSpacing.screen,
        ),
        const SizedBox(width: EdenSpacing.sm),
        Expanded(
          child: Text(
            error,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: EdenDarkColors.error),
          ),
        ),
      ],
    ),
  );
}

class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirm,
    this.icon = Icons.check,
  });
  final String label;
  final VoidCallback? onConfirm;
  final IconData icon;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  double _progress = 0;

  void _confirm() {
    HapticFeedback.lightImpact();
    widget.onConfirm?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onConfirm != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final travel = (constraints.maxWidth - EdenSpacing.control).clamp(
          1.0,
          double.infinity,
        );
        return Semantics(
          button: true,
          enabled: enabled,
          label: widget.label,
          onTap: enabled ? _confirm : null,
          child: ExcludeSemantics(
            child: GestureDetector(
              onHorizontalDragUpdate: !enabled
                  ? null
                  : (event) => setState(
                      () => _progress = (_progress + event.delta.dx / travel)
                          .clamp(0.0, 1.0),
                    ),
              onHorizontalDragEnd: !enabled
                  ? null
                  : (_) {
                      final confirmed = _progress >= .85;
                      setState(() => _progress = 0);
                      if (confirmed) _confirm();
                    },
              onHorizontalDragCancel: !enabled
                  ? null
                  : () => setState(() => _progress = 0),
              child: Ink(
                height: EdenSpacing.control,
                decoration: const ShapeDecoration(
                  color: EdenDarkColors.glass,
                  shape: StadiumBorder(),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: EdenSpacing.control,
                      ),
                      child: Text(widget.label, textAlign: TextAlign.center),
                    ),
                    const Positioned(
                      right: EdenSpacing.screen,
                      child: Icon(
                        Icons.double_arrow,
                        color: EdenDarkColors.secondary,
                      ),
                    ),
                    Positioned(
                      left: _progress * travel,
                      child: SizedBox.square(
                        dimension: EdenSpacing.control,
                        child: Material(
                          color: enabled
                              ? EdenDarkColors.accent
                              : EdenDarkColors.strongGlass,
                          shape: const CircleBorder(),
                          child: IconButton(
                            onPressed: enabled ? _confirm : null,
                            tooltip: widget.label,
                            icon: Icon(widget.icon),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum EdenStatus { pending, live, complete, neutral }

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.status = EdenStatus.neutral,
  });
  final String label;
  final EdenStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      EdenStatus.pending => EdenDarkColors.warning,
      EdenStatus.live => EdenDarkColors.accent,
      EdenStatus.complete => EdenDarkColors.success,
      EdenStatus.neutral => EdenDarkColors.secondary,
    };
    return Chip(
      avatar: Icon(Icons.circle, size: EdenSpacing.sm, color: color),
      label: Text(label),
      backgroundColor: EdenDarkColors.glass,
      shape: const StadiumBorder(
        side: BorderSide(color: EdenDarkColors.strongGlass),
      ),
    );
  }
}

class StatusStepper extends StatelessWidget {
  const StatusStepper({super.key, required this.labels, required this.current});
  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < labels.length; i++)
        ListTile(
          leading: Icon(
            i < current
                ? Icons.check_circle_outline
                : i == current
                ? Icons.radio_button_checked
                : Icons.circle_outlined,
            color: i < current
                ? EdenDarkColors.success
                : i == current
                ? EdenDarkColors.accent
                : EdenDarkColors.secondary,
          ),
          title: Text(labels[i]),
          selected: i == current,
        ),
    ],
  );
}

class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(EdenSpacing.screen),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(EdenRadius.pill),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelected,
            backgroundColor: EdenDarkColors.strongGlass,
            indicatorColor: EdenDarkColors.accent,
            destinations: destinations,
          ),
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    required this.action,
  });
  final IconData icon;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => GlassCard(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(backgroundColor: EdenDarkColors.glass, child: Icon(icon)),
        const SizedBox(height: EdenSpacing.screen),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: EdenSpacing.screen),
        action,
      ],
    ),
  );
}

class SuccessSeal extends StatelessWidget {
  const SuccessSeal({super.key});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: .7, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 360),
    curve: Curves.easeOutBack,
    builder: (context, value, child) => Transform.rotate(
      angle: (value - 1) / 2,
      child: Transform.scale(scale: value, child: child),
    ),
    child: const Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          Icons.workspace_premium,
          color: EdenDarkColors.accent,
          size: EdenSpacing.control * 2,
        ),
        Icon(Icons.check, color: EdenDarkColors.text, size: EdenSpacing.large),
      ],
    ),
  );
}

class ShimmerBox extends StatelessWidget {
  const ShimmerBox({super.key, this.height = EdenSpacing.control});
  final double height;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 650),
    builder: (context, value, _) => Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EdenRadius.field),
        gradient: LinearGradient(
          begin: Alignment(-2 + value * 3, 0),
          end: Alignment(-1 + value * 3, 0),
          colors: const [
            EdenDarkColors.glass,
            EdenDarkColors.strongGlass,
            EdenDarkColors.glass,
          ],
        ),
      ),
    ),
  );
}
