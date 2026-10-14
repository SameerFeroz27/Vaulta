import 'package:flutter/material.dart';

import '../../utils/formatters.dart';

/// Reusable card showing a labeled amount with an icon.
class SummaryCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;
  final String currency;

  /// Opens the tile's detail. Null leaves the card inert.
  final VoidCallback? onTap;

  /// The card's outer spacing. A caller that wraps the card in its own layout — a growing
  /// container, say — passes zero and owns the padding itself.
  final EdgeInsetsGeometry margin;

  const SummaryCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
    this.currency = 'PKR',
    this.onTap,
    this.margin = const EdgeInsets.symmetric(horizontal: 2),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  Formatters.currency(amount, code: currency),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
