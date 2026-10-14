import 'package:flutter/material.dart';

import '../../config/motion.dart';

/// One destination in the flat bottom bar.
class AppNavDestination {
  final IconData icon;
  final String label;

  /// A count to show on the icon's badge. Null or 0 hides the badge.
  final int? badgeCount;

  const AppNavDestination({
    required this.icon,
    required this.label,
    this.badgeCount,
  });
}

/// The flat bottom navigation bar.
///
/// A plain surface — no tonal pill, no per-item indicator — where the selection is marked
/// by a single 3 px primary line across the top edge of the selected destination. The line
/// is one widget that glides between equal-width slots, which [NavigationBar] cannot do, so
/// this is hand-built.
class AppBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AppNavDestination> destinations;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.destinations,
  });

  static const double _height = 64;

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav>
    with SingleTickerProviderStateMixin {
  /// Drives the glide. An explicit controller rather than an `AnimatedPositioned` because
  /// implicit animations cannot opt out of Flutter's reduce-motion scaling, and this line
  /// is meant to always glide in full.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.indicator,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// Destination indices the line is travelling between.
  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _from = _to = widget.currentIndex.toDouble();
  }

  @override
  void didUpdateWidget(covariant AppBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex == widget.currentIndex) return;
    _from = _to;
    _to = widget.currentIndex.toDouble();
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: SizedBox(
          height: AppBottomNav._height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Destinations are equal width, so the selected slot's offset is arithmetic.
              final slot = constraints.maxWidth / widget.destinations.length;

              return Stack(
                children: [
                  // One line, gliding between destinations. The first placement carries no
                  // animation because there is no previous position to travel from.
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final t = Motion.emphasized.transform(_controller.value);
                      final position = _from + (_to - _from) * t;
                      return Positioned(
                        left: slot * position,
                        top: 0,
                        width: slot,
                        height: 3,
                        child: ColoredBox(
                          key: const Key('nav-indicator'),
                          color: scheme.primary,
                        ),
                      );
                    },
                  ),
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (
                          var i = 0;
                          i < widget.destinations.length;
                          i++
                        )
                          Expanded(
                            child: _Destination(
                              destination: widget.destinations[i],
                              selected: i == widget.currentIndex,
                              onTap: () => widget.onTap(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _Destination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icons stay outlined in both states; the top line marks the selection.
            Badge.count(
              count: destination.badgeCount ?? 0,
              isLabelVisible: (destination.badgeCount ?? 0) > 0,
              child: Icon(destination.icon, size: 24, color: color),
            ),
            const SizedBox(height: 2),
            // 12 px keeps every label inside its slot at any phone width.
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
