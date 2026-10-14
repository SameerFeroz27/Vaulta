import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/loan.dart';
import '../../providers/loan_provider.dart';
import '../../utils/formatters.dart';
import '../common/empty_state.dart';
import '../common/error_state.dart';
import '../dashboard/tile_detail.dart';
import 'loan_summary_table.dart';

/// The "By person" tab: every person's standing, aggregated across their loans.
///
/// Its own tab because it answers a different question from the loan list — who do I
/// stand where with, rather than which loans exist — and it counts removed loans, so
/// the two figures legitimately differ.
class LoanPersonSummaryView extends StatelessWidget {
  final VoidCallback onAddLoan;

  const LoanPersonSummaryView({required this.onAddLoan, super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LoanProvider>();

    if (provider.isLoading && provider.summary.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.summary.isEmpty) {
      return ErrorState(message: provider.error!, onRetry: provider.loadLoans);
    }

    return RefreshIndicator(
      onRefresh: provider.loadLoans,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          if (provider.summary.isEmpty)
            SizedBox(height: 280, child: _buildEmptyState())
          else
            LoanSummaryTable(
              people: provider.summary,
              // A row grows into that person's own standing — the same rows, magnified.
              personDetailBuilder: (context, person) =>
                  _personDetail(person),
            ),
        ],
      ),
    );
  }

  /// The detail a By-person row grows into: the same owed / owe / net figures, signed and
  /// coloured the way the row shows them.
  Widget _personDetail(LoanSummaryPerson person) {
    return TileDetailScreen(
      title: person.person,
      rows: [
        _moneyRow('Owed to me', person.theyOwe, Colors.green[700]),
        _moneyRow('I owe', person.iOwe, Colors.red[700]),
        _netRow(person.net),
      ],
      note: person.loanCount == 0
          ? 'No active loans — their repayment history is kept.'
          : null,
    );
  }

  TileDetailRow _moneyRow(String label, double amount, Color? color) =>
      TileDetailRow(
        label,
        amount == 0 ? '—' : Formatters.currency(amount),
        valueColor: amount == 0 ? Colors.grey[500] : color,
      );

  TileDetailRow _netRow(double net) {
    if (net == 0) {
      return TileDetailRow('Net', '—', valueColor: Colors.grey[500]);
    }
    return TileDetailRow(
      'Net',
      '${net > 0 ? '+' : '-'}${Formatters.currency(net.abs())}',
      valueColor: net > 0 ? Colors.green[700] : Colors.red[700],
      bold: true,
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: Icons.groups_outlined,
      title: 'No one to show yet',
      subtitle: 'People appear here once you record a loan with them.',
      action: FilledButton.icon(
        onPressed: onAddLoan,
        icon: const Icon(Icons.add),
        label: const Text('Add a loan'),
      ),
    );
  }
}
