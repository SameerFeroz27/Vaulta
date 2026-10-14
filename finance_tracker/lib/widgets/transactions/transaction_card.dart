import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../models/transaction.dart';
import '../../utils/formatters.dart';

class TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback? onTap;

  /// The card's outer spacing. A caller that wraps the card in its own layout — a growing
  /// container, say — passes zero and owns the padding itself, so the container's surface
  /// lines up with the card rather than its margin.
  final EdgeInsetsGeometry margin;

  const TransactionCard({
    required this.transaction,
    this.onTap,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    super.key,
  });

  Color _parseColor(String? hex) {
    if (hex == null) return Colors.grey.shade300;
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final amountColor = t.isExpense
        ? AppTheme.expenseFor(context)
        : AppTheme.incomeFor(context);
    final amountPrefix = t.isExpense ? '-' : '+';
    final numberFormat = Formatters.currency(t.amount, code: t.currency);

    return Card(
      margin: margin,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _parseColor(t.categoryColor).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    t.categoryIcon ?? '📁',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            t.merchant ?? t.categoryName ?? 'Transaction',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (t.needsReview) ...[
                          const SizedBox(width: 6),
                          const _ReviewBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Formatters.shortDate(t.transactionDate)} • ${t.sourceName}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$amountPrefix$numberFormat',
                style: TextStyle(
                  color: amountColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marks a transaction whose direction the AI could not settle, so it is excluded
/// from dashboard totals until the user confirms or changes it.
class _ReviewBadge extends StatelessWidget {
  const _ReviewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Review',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.orange,
        ),
      ),
    );
  }
}
