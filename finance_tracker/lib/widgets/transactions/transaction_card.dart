import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../models/transaction.dart';
import '../../utils/formatters.dart';

class TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback? onTap;

  const TransactionCard({
    required this.transaction,
    this.onTap,
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
        ? AppTheme.expenseColor
        : AppTheme.incomeColor;
    final amountPrefix = t.isExpense ? '-' : '+';
    final numberFormat = Formatters.currency(t.amount, code: t.currency);

    return Card(
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
                    Text(
                      t.merchant ?? t.categoryName ?? 'Transaction',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
