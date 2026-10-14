import 'package:flutter/material.dart';

import '../../config/motion.dart';

/// An [AnimationController] that plays in full even when the OS asks for reduced motion.
///
/// Flutter runs every default-behaviour controller at 5% of its duration while
/// `AccessibilityFeatures.disableAnimations` is set (`animation_controller.dart`, the
/// `AnimationBehavior.normal` path), which makes a transition read as an instant cut.
/// `AnimationBehavior.preserve` is the only opt-out, and a route owns its transition
/// controller — so a route is the only place it can be applied to page transitions.
AnimationController fullMotionController(
  TickerProvider vsync, {
  required Duration duration,
  required Duration reverseDuration,
  required String debugLabel,
}) {
  return AnimationController(
    vsync: vsync,
    debugLabel: debugLabel,
    duration: duration,
    reverseDuration: reverseDuration,
    animationBehavior: AnimationBehavior.preserve,
  );
}

/// A [MaterialPageRoute] whose transition plays in full regardless of the OS
/// reduce-motion setting, keeping the platform's own page transition.
class FullMotionPageRoute<T> extends MaterialPageRoute<T> {
  FullMotionPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });

  @override
  AnimationController createAnimationController() {
    return fullMotionController(
      navigator!,
      duration: transitionDuration,
      reverseDuration: reverseTransitionDuration,
      debugLabel: '$runtimeType',
    );
  }
}

/// The tile → detail transform: the target screen is laid out full size and clipped to a
/// rect that starts as the tile that was tapped and expands to the whole screen, with the
/// surface colour easing from the tile's own colour to the page's.
///
/// This is the prototype's container transform. It replaces the `animations` package's
/// `OpenContainer`, whose route cannot opt out of the reduce-motion scaling and which
/// allocates two [GlobalKey]s per tile — a real cost once every list row carries one.
class ContainerTransformRoute<T> extends PageRouteBuilder<T> {
  ContainerTransformRoute({
    required Rect fromRect,
    required BorderRadius fromRadius,
    required Color fromColor,
    required Color toColor,
    required WidgetBuilder builder,
    super.settings,
  }) : super(
         // Not opaque: outside the growing rect the screen underneath must stay visible,
         // which is what makes the tile look like it is growing out of itself.
         opaque: false,
         transitionDuration: Motion.container,
         reverseTransitionDuration: Motion.collapse,
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionsBuilder:
             (context, animation, secondaryAnimation, child) =>
                 _ContainerTransform(
                   animation: animation,
                   fromRect: fromRect,
                   fromRadius: fromRadius,
                   fromColor: fromColor,
                   toColor: toColor,
                   child: child,
                 ),
       );

  @override
  AnimationController createAnimationController() {
    return fullMotionController(
      navigator!,
      duration: transitionDuration,
      reverseDuration: reverseTransitionDuration,
      debugLabel: '$runtimeType',
    );
  }
}

class _ContainerTransform extends StatelessWidget {
  final Animation<double> animation;
  final Rect fromRect;
  final BorderRadius fromRadius;
  final Color fromColor;
  final Color toColor;
  final Widget child;

  const _ContainerTransform({
    required this.animation,
    required this.fromRect,
    required this.fromRadius,
    required this.fromColor,
    required this.toColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Motion.emphasized.transform(animation.value.clamp(0.0, 1.0));
        final rect = Rect.lerp(fromRect, Offset.zero & screen, t)!;
        final radius = BorderRadius.lerp(fromRadius, BorderRadius.zero, t)!;
        final color = Color.lerp(fromColor, toColor, t)!;
        // The content arrives over the back half, so the grow is read first and the detail
        // does not animate on the same beat as the surface carrying it.
        final contentOpacity = ((t - 0.35) / 0.65).clamp(0.0, 1.0);

        return ClipPath(
          clipper: _GrowClipper(rect: rect, radius: radius),
          child: ColoredBox(
            color: color,
            child: Opacity(opacity: contentOpacity, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

class _GrowClipper extends CustomClipper<Path> {
  final Rect rect;
  final BorderRadius radius;

  const _GrowClipper({required this.rect, required this.radius});

  @override
  Path getClip(Size size) => Path()..addRRect(radius.toRRect(rect));

  @override
  bool shouldReclip(_GrowClipper oldClipper) =>
      oldClipper.rect != rect || oldClipper.radius != radius;
}
