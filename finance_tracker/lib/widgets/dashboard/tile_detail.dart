import 'package:flutter/material.dart';

/// One label/value line in a [TileDetailScreen].
class TileDetailRow {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const TileDetailRow(
    this.label,
    this.value, {
    this.valueColor,
    this.bold = false,
  });
}

/// The detail a dashboard tile grows into.
///
/// Its rows are mirrored from the tile that was tapped — the same figures, magnified — so a
/// detail can never disagree with the card it came from.
class TileDetailScreen extends StatelessWidget {
  final String title;
  final String? heroAmount;
  final String? heroLabel;
  final Color? heroColor;
  final List<TileDetailRow> rows;

  /// An optional primary action, such as "See all loans".
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? note;

  const TileDetailScreen({
    super.key,
    required this.title,
    this.heroAmount,
    this.heroLabel,
    this.heroColor,
    this.rows = const [],
    this.actionLabel,
    this.onAction,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (heroAmount != null) ...[
            Text(
              heroAmount!,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: heroColor,
              ),
            ),
            if (heroLabel != null) ...[
              const SizedBox(height: 3),
              Text(
                heroLabel!,
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ],
            const SizedBox(height: 16),
          ],
          for (final row in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      row.value,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            row.bold ? FontWeight.w700 : FontWeight.w600,
                        color: row.valueColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (actionLabel != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
          if (note != null) ...[
            const SizedBox(height: 16),
            Text(
              note!,
              style: TextStyle(fontSize: 12, height: 1.5, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
