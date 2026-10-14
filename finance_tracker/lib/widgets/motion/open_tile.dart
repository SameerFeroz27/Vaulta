import 'package:flutter/material.dart';

import 'full_motion_route.dart';

/// A tile that grows into its own detail with the prototype's container transform.
///
/// The tile is built with the [openContainer] callback so it can drive the open from its
/// own tap target. That is what lets an inner action — a payment pill, a link — consume its
/// own tap instead of fighting an outer tap layer.
///
/// [margin] sits *outside* the growing surface, and the tile itself must carry no margin, so
/// the surface lines up with the tile's rectangle rather than its spacing. That is what
/// makes the grow start as the tile the user actually touched. Set [radius] to the tile's
/// own corner radius so the starting shape matches too.
class OpenTile extends StatelessWidget {
  final Widget Function(BuildContext context, VoidCallback openContainer)
  tileBuilder;
  final WidgetBuilder detailBuilder;
  final double radius;
  final EdgeInsetsGeometry margin;

  /// Called once the detail has closed, so a caller can refresh what the detail may have
  /// changed.
  final VoidCallback? onClosed;

  const OpenTile({
    super.key,
    required this.tileBuilder,
    required this.detailBuilder,
    this.radius = 12,
    this.margin = EdgeInsets.zero,
    this.onClosed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: margin,
      // The boundary caches the tile's raster, and gives the open callback a context whose
      // render object is the tile itself — so the starting rectangle needs no GlobalKey.
      child: RepaintBoundary(
        child: Builder(
          builder: (tileContext) =>
              tileBuilder(tileContext, () => _open(tileContext, theme)),
        ),
      ),
    );
  }

  void _open(BuildContext tileContext, ThemeData theme) {
    final box = tileContext.findRenderObject() as RenderBox?;
    final fromRect = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    final route = ContainerTransformRoute<void>(
      // A tile whose geometry cannot be read still opens, just without the grow.
      fromRect: fromRect ?? Rect.zero,
      fromRadius: BorderRadius.circular(radius),
      // The tile paints the surface, so the grow starts from that colour.
      fromColor: theme.cardTheme.color ?? theme.colorScheme.surface,
      toColor: theme.scaffoldBackgroundColor,
      builder: detailBuilder,
    );

    final closed = Navigator.of(tileContext).push(route);
    if (onClosed != null) closed.whenComplete(onClosed!);
  }
}
