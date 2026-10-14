import 'package:flutter/material.dart';

import '../../widgets/common/button_spinner.dart';
import '../../widgets/motion/stagger.dart';

/// Shared chrome for the pre-auth screens (sign in, register, forgot and reset password).
///
/// The reviewed "Plain" layout: no app bar, a tonal brand block with the wordmark and a
/// one-line purpose, then the form. Every one of the four screens uses this rather than
/// inventing its own, so they stay in step.
///
/// The spacing is deliberately tight so the whole screen fits a standard phone height
/// without scrolling, and it draws no scrollbar — the scroll view below is only a fallback
/// for a very short viewport or an open keyboard.
class AuthLayout extends StatelessWidget {
  /// The one-line purpose under the wordmark.
  final String tagline;

  /// The form column.
  final Widget child;

  /// A short line under the form. Only true statements go here.
  final String? footer;

  const AuthLayout({
    super.key,
    required this.tagline,
    required this.child,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ScrollConfiguration(
          // No scrollbar here: the layout is built to fit, so a track would only ever be an
          // empty decoration. Scrolling still works as an overflow fallback.
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    // The screen fills the viewport: the brand opens it, the form sits in
                    // the middle and the privacy line closes it, so a tall phone never ends
                    // in an empty tail below the form. When the content is taller than the
                    // viewport the gaps collapse and the screen scrolls instead.
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      StaggerItem(
                        index: 0,
                        child: Column(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 26,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Vaulta',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tagline,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            // A floor under the gap between the brand and the form, so the
                            // two never touch when the content fills the height.
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                      StaggerItem(index: 1, child: child),
                      // The last slot holds the bottom edge even when there is no footer,
                      // which is what keeps the form sitting in the middle.
                      if (footer != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(
                            footer!,
                            textAlign: TextAlign.center,
                            // A trust message has to be readable, so it takes a near-body
                            // colour rather than the faint grey secondary text usually gets.
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              color: scheme.onSurface.withValues(alpha: 0.85),
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports a failed sign-in inline, the calmer native pattern, rather than firing a
/// snackbar over the form.
class AuthErrorBanner extends StatelessWidget {
  final String message;

  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A text link sized to a comfortable touch target.
///
/// Material already pads a [TextButton]'s tap area out to 48 px, but pinning a 44 px minimum
/// height makes the requirement explicit and survives a future theme change.
class AuthTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const AuthTextButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
      child: Text(label),
    );
  }
}

/// The full-width submit button: its own spinner while busy, a 48 px target so it is easy to
/// hit, and marked busy for accessibility so a screen reader announces the wait.
class AuthSubmitButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !busy,
      // Announced while the request is in flight, so the wait is not silent to a reader.
      liveRegion: busy,
      label: label,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: busy ? const ButtonSpinner() : Text(label),
      ),
    );
  }
}

/// A one-shot horizontal shake, used when a submit is rejected.
///
/// Wrong details get a shake because it says "not that" without moving anything the user is
/// reading.
class Shake extends StatefulWidget {
  /// Increment to trigger. Any change replays the shake.
  final int trigger;
  final Widget child;

  const Shake({super.key, required this.trigger, required this.child});

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    // Full motion even when the OS asks for reduced motion.
    animationBehavior: AnimationBehavior.preserve,
  );

  late final Animation<double> _offset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -6.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 6.0, end: -4.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -4.0, end: 4.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 4.0, end: 0.0), weight: 1),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant Shake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger == widget.trigger) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) =>
          Transform.translate(offset: Offset(_offset.value, 0), child: child),
      child: widget.child,
    );
  }
}
