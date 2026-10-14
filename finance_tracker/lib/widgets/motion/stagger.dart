import 'package:flutter/material.dart';

import '../../config/motion.dart';

/// Carries a per-tab "entry" counter down the tree.
///
/// The tab bodies live in an [IndexedStack], so they are not rebuilt when the user returns
/// to a tab — which means a list animation would otherwise play only once, on first build.
/// The shell bumps the selected tab's [tick] on every entry, and each [StaggerItem] below
/// replays when the tick changes.
class StaggerReplay extends InheritedWidget {
  final int tick;

  const StaggerReplay({super.key, required this.tick, required super.child});

  static int? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<StaggerReplay>()
      ?.tick;

  @override
  bool updateShouldNotify(StaggerReplay oldWidget) => oldWidget.tick != tick;
}

/// One row of a staggered list.
///
/// The row rises and fades in, 40 ms after the one before it, and nothing past
/// [Motion.staggerMax] waits its turn.
class StaggerItem extends StatefulWidget {
  /// Position in the list — the item's turn is [index] × 40 ms, capped by the motion spec.
  final int index;

  /// The list this item belongs to. Changing it restarts the animation, so a list that is
  /// reused for a different screen replays rather than staying settled.
  final Object? listKey;

  final Widget child;

  const StaggerItem({
    super.key,
    required this.index,
    this.listKey,
    required this.child,
  });

  @override
  State<StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<StaggerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    // Opts out of Flutter's 5%-duration scaling when the OS requests reduced motion, so the
    // stagger always plays in full.
    animationBehavior: AnimationBehavior.preserve,
  );

  int? _tick;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = StaggerReplay.maybeOf(context) ?? 0;
    if (_tick != tick) {
      _tick = tick;
      _start();
    }
  }

  void _start() {
    final generation = ++_generation;

    _controller.value = 0;
    final delay = Motion.staggerFor(widget.index);
    if (delay == Duration.zero) {
      _controller.forward();
      return;
    }
    Future.delayed(delay, () {
      if (mounted && generation == _generation) _controller.forward();
    });
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.value == 1) return child!;
        final t = Motion.standard.transform(_controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
        );
      },
      child: widget.child,
    );
  }
}
