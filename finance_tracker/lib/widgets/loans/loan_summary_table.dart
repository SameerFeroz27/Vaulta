import 'package:flutter/material.dart';

import '../../models/loan.dart';
import '../../utils/formatters.dart';
import '../motion/open_tile.dart';

/// Every person's standing across their active loans.
///
/// One stacked block per person rather than a column grid. At phone width a four-column
/// table leaves each money column about 70px, so any larger amount either truncates or
/// gets scaled down to a different size than the row above it — which is what made the
/// figures hard to read. Giving each amount its own right-aligned line means any amount
/// fits at a consistent size and the values still line up down the card.
class LoanSummaryTable extends StatelessWidget {
  final List<LoanSummaryPerson> people;

  /// When provided, a person's row grows into that person's own detail — the same owed /
  /// owe / net rows, magnified. Null leaves the rows as plain table rows.
  final Widget Function(BuildContext context, LoanSummaryPerson person)?
      personDetailBuilder;

  const LoanSummaryTable({
    required this.people,
    this.personDetailBuilder,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();

    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final totalTheyOwe = people.fold<double>(0, (total, p) => total + p.theyOwe);
    final totalIOwe = people.fold<double>(0, (total, p) => total + p.iOwe);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < people.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _personRow(context, people[i], muted),
            ],
            if (people.length > 1) ...[
              const Divider(height: 1),
              _totalsBlock(totalTheyOwe, totalIOwe, muted),
            ],
          ],
        ),
      ),
    );
  }

  Widget _personRow(
    BuildContext context,
    LoanSummaryPerson person,
    Color muted,
  ) {
    final block = _personBlock(person, muted);
    final detailBuilder = personDetailBuilder;
    if (detailBuilder == null) return block;

    // The row is transparent — it sits on the card's surface — so the grow starts from that
    // surface's colour, and from a square corner to match the row's own shape.
    return OpenTile(
      radius: 0,
      tileBuilder: (context, open) => InkWell(onTap: open, child: block),
      detailBuilder: (context) => detailBuilder(context, person),
    );
  }

  Widget _personBlock(LoanSummaryPerson person, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  person.person,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _statusLabel(person),
                style: TextStyle(fontSize: 11, color: _statusColor(person)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _moneyLine('Owed to me', person.theyOwe, Colors.green[700], muted),
          const SizedBox(height: 5),
          _moneyLine('I owe', person.iOwe, Colors.red[700], muted),
          const SizedBox(height: 5),
          _moneyLine('Net', person.net, null, muted, signed: true),
        ],
      ),
    );
  }

  Widget _totalsBlock(double theyOwe, double iOwe, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _moneyLine('Owed to me', theyOwe, Colors.green[700], muted, bold: true),
          const SizedBox(height: 5),
          _moneyLine('I owe', iOwe, Colors.red[700], muted, bold: true),
          const SizedBox(height: 5),
          _moneyLine('Net', theyOwe - iOwe, null, muted, signed: true, bold: true),
        ],
      ),
    );
  }

  /// A label with its amount on the same line, the amount right-aligned so figures line
  /// up down the card. Zero renders as a dash — an empty cell reads as "nothing".
  Widget _moneyLine(
    String label,
    double amount,
    Color? color,
    Color muted, {
    bool signed = false,
    bool bold = false,
  }) {
    final String value;
    Color? valueColor = color;

    if (amount == 0) {
      value = '—';
      valueColor = Colors.grey[500];
    } else if (signed) {
      value = '${amount > 0 ? '+' : '-'}${Formatters.currency(amount.abs())}';
      valueColor = amount > 0 ? Colors.green[700] : Colors.red[700];
    } else {
      value = Formatters.currency(amount);
    }

    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontSize: 13, color: muted)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  /// A person stays listed after their loans are removed, because their repayment
  /// history is kept. Saying "no active loans" beats an unexplained empty row.
  String _statusLabel(LoanSummaryPerson person) {
    if (person.loanCount == 0) return 'No active loans';
    return person.isOpen ? 'Open' : 'Settled';
  }

  Color _statusColor(LoanSummaryPerson person) {
    if (person.loanCount == 0) return Colors.grey[600]!;
    return person.isOpen ? Colors.orange[800]! : Colors.green[700]!;
  }
}
