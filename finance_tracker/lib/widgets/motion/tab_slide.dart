import 'package:flutter/material.dart';

import '../../config/motion.dart';

/// Enter-only slide for a tab switch.
///
/// The app keeps an [IndexedStack] because it is what preserves each tab's scroll state,
/// and a `PageTransitionSwitcher` would dispose the outgoing tab. So this slides the
/// incoming child in from the side the tab order came from — a later tab from the right,
/// an earlier one from the left — while the stack itself stays put. Because the stack only
/// paints the active child, translating it reads as the new screen arriving.
class TabSlide extends StatefulWidget {
  /// The index now selected, so the direction of travel can be worked out.
  final int index;
  final Widget child;

  const TabSlide({super.key, required this.index, required this.child});

  @override
  State<TabSlide> createState() => _TabSlideState();
}

class _TabSlideState extends State<TabSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.tabSlide,
    value: 1,
    // Full motion is asked for unconditionally. Flutter scales every default-behaviour
    // controller to 5% of its duration when the OS requests reduced motion; `preserve` is
    // the opt-out.
    animationBehavior: AnimationBehavior.preserve,
  );

  /// Where the incoming screen starts, as a fraction of its width.
  double _beginFraction = 0;

  @override
  void didUpdateWidget(covariant TabSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;

    _beginFraction = widget.index > oldWidget.index ? 0.072 : -0.072;
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
      animation: _controller,
      builder: (context, child) {
        final t = Motion.emphasized.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: FractionalTranslation(
            translation: Offset(_beginFraction * (1 - t), 0),
            child: child,
          ),
        );
      },
      // The boundary lets the fade reuse the tab's cached raster each frame instead of
      // recompositing the whole screen (charts included) for the length of the slide.
      child: RepaintBoundary(child: widget.child),
    );
  }
}
