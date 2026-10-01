import 'package:flutter/material.dart';

import '../../models/loan.dart';
import '../../utils/formatters.dart';

/// One loan in the list: who, how much is still owed, how far along, and when due.
class LoanCard extends StatelessWidget {
  final Loan loan;
  final VoidCallback onTap;

  const LoanCard({required this.loan, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // Owed to me is money coming back; what I owe is money going out.
    final amountColor = loan.isLent ? Colors.green[700]! : Colors.red[700]!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                loan.counterparty,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (loan.overdue) ...[
                              const SizedBox(width: 8),
                              _Chip(label: 'Overdue', color: Colors.red[700]!),
                            ] else if (loan.isSettled) ...[
                              const SizedBox(width: 8),
                              _Chip(label: 'Settled', color: Colors.green[700]!),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(),
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // An overpaid loan headlines the surplus, because nothing is
                      // outstanding and "₨ 0.00" there reads as unfinished rather than
                      // settled.
                      Text(
                        Formatters.currency(
                          loan.hasSurplus ? loan.surplus : loan.outstanding,
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: loan.hasSurplus
                              ? Colors.blue[700]
                              : (loan.isSettled ? muted : amountColor),
                        ),
                      ),
                      Text(
                        loan.hasSurplus
                            ? 'over the amount'
                            : (loan.isSettled ? 'nothing outstanding' : 'outstanding'),
                        style: TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: loan.progress,
                  minHeight: 5,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    loan.isSettled ? Colors.green[600]! : theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Flexible so a long amount cannot push the due date out of the card.
                  Flexible(
                    child: Text(
                      '${Formatters.currency(loan.paid)} of ${Formatters.currency(loan.principal)} repaid',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                  if (loan.dueDate != null)
                    Text(
                      'Due ${Formatters.shortDate(loan.dueDate!)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: loan.overdue ? Colors.red[700] : muted,
                        fontWeight: loan.overdue ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[loan.directionLabel];
    if (!loan.isSettled) {
      parts.add('${(loan.progress * 100).round()}% repaid');
    } else {
      parts.add('fully repaid');
    }
    return parts.join(' · ');
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
