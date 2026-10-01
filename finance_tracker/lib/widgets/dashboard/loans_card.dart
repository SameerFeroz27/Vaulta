import 'package:flutter/material.dart';

import '../../utils/formatters.dart';

/// Dashboard section showing the lending position: what is owed to the user, what they
/// owe, and — only when something is actually late — who is overdue.
/// Taps through to the Loans tab.
class LoansCard extends StatelessWidget {
  /// Amounts arrive in PKR — loans are PKR-only by design.
  final double theyOwe;
  final double iOwe;

  /// Who is overdue, one entry per person. Empty when nothing is overdue.
  final List<String> overduePeople;
  final int overdueCount;

  /// The user's base currency. When it is not PKR the totals are converted using
  /// [exchangeRates]; without a rate they are shown in PKR, which the ₨ symbol marks.
  final String currency;
  final Map<String, double>? exchangeRates;
  final VoidCallback onTap;

  const LoansCard({
    required this.theyOwe,
    required this.iOwe,
    required this.onTap,
    this.overduePeople = const [],
    this.overdueCount = 0,
    this.currency = 'PKR',
    this.exchangeRates,
    super.key,
  });

  /// Returns the display amount and the currency code it is actually in.
  ({double amount, String code}) _convert(double pkr) {
    if (currency == 'PKR') return (amount: pkr, code: 'PKR');

    final rate = exchangeRates?['PKR'];
    if (rate != null && rate > 0) return (amount: pkr * rate, code: currency);

    return (amount: pkr, code: 'PKR');
  }

  bool get _hasOverdue => overdueCount > 0 || overduePeople.isNotEmpty;

  /// "Ali" for one person, "Ali, +1 more" beyond that.
  String get _overdueLabel {
    if (overduePeople.isEmpty) {
      return overdueCount == 1 ? '1 overdue' : '$overdueCount overdue';
    }
    if (overduePeople.length == 1) return overduePeople.first;
    return '${overduePeople.first}, +${overduePeople.length - 1} more';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.handshake_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Loans',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 20, color: muted),
                ],
              ),
              const SizedBox(height: 10),
              _line(context, 'Owed to me', _convert(theyOwe), Colors.green[700]!),
              const SizedBox(height: 4),
              _line(context, 'I owe', _convert(iOwe), Colors.red[700]!),

              // Shown only when something is actually late — otherwise the card is
              // just the two balances.
              if (_hasOverdue) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Colors.red[700],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Overdue: $_overdueLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    ({double amount, String code}) value,
    Color color,
  ) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Text('$label: ', style: TextStyle(fontSize: 13, color: muted)),
        Text(
          Formatters.currency(value.amount, code: value.code),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
