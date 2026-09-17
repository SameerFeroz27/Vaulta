import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../utils/formatters.dart';

/// Progress bar showing budget vs actual spending.
class BudgetProgressCard extends StatelessWidget {
  final String label;
  final double budgetAmount;
  final double spent;
  final double percentage;
  final bool overBudget;
  final String? icon;
  final String? colorHex;
  final String currency;

  const BudgetProgressCard({
    required this.label,
    required this.budgetAmount,
    required this.spent,
    required this.percentage,
    required this.overBudget,
    this.icon,
    this.colorHex,
    this.currency = 'PKR',
    super.key,
  });

  Color get _color {
    if (overBudget) return AppTheme.expenseColor;
    if (colorHex != null) {
      final clean = colorHex!.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    }
    return const Color(0xFF1976D2);
  }

  @override
  Widget build(BuildContext context) {
    final clampedPercent = percentage.clamp(0, 100);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Text(icon!, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (overBudget)
                  const Icon(
                    Icons.warning,
                    size: 16,
                    color: AppTheme.expenseColor,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: clampedPercent / 100,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                color: _color,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Spent: ${Formatters.currency(spent, code: currency)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
                Text(
                  'Budget: ${Formatters.currency(budgetAmount, code: currency)}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
