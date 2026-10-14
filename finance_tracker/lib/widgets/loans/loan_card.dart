import 'package:flutter/material.dart';

import '../../models/loan.dart';
import '../../utils/formatters.dart';

/// One loan in the list: who, how much is still owed, how far along, and when due.
class LoanCard extends StatelessWidget {
  final Loan loan;
  final VoidCallback onTap;

  /// When provided, a "Record payment" action sits on the card's footer row so a repayment
  /// can be made without opening the detail first.
  final VoidCallback? onRecordPayment;

  /// The card's outer spacing. A caller that wraps the card in its own layout — a growing
  /// container, say — passes zero and owns the padding itself, so the container's surface
  /// lines up with the card rather than its margin.
  final EdgeInsetsGeometry margin;

  const LoanCard({
    required this.loan,
    required this.onTap,
    this.onRecordPayment,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // Owed to me is money coming back; what I owe is money going out.
    final amountColor = loan.isLent ? Colors.green[700]! : Colors.red[700]!;

    return Card(
      margin: margin,
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
                        // What is left leads, because that is the figure the user acts on.
                        // The original amount sits on the footer line beneath it.
                        loan.hasSurplus
                            ? 'over the amount'
                            : (loan.isSettled ? 'nothing outstanding' : 'left'),
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
                children: [
                  // Flexible so a long amount cannot push the payment action out of the card.
                  Expanded(
                    child: Text(
                      _footerLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: loan.overdue ? Colors.red[700] : muted,
                        fontWeight:
                            loan.overdue ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (onRecordPayment != null) ...[
                    const SizedBox(width: 8),
                    _PayButton(onTap: onRecordPayment!),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The original amount and the due date on one line, so what is still left stays the
  /// headline above. A loan with no due date says so rather than leaving a gap.
  String _footerLabel() {
    final parts = <String>['of ${Formatters.currency(loan.principal)}'];
    parts.add(
      loan.dueDate == null
          ? 'No due date'
          : 'Due ${Formatters.shortDate(loan.dueDate!)}',
    );
    return parts.join(' · ');
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

/// The tonal "Record payment" pill on the card footer. Its own tap target consumes the tap,
/// so it opens the sheet rather than the loan detail behind it.
class _PayButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PayButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final radius = BorderRadius.circular(12);

    return Material(
      color: primary.withValues(alpha: 0.12),
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Text(
            'Record payment',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
        ),
      ),
    );
  }
}
