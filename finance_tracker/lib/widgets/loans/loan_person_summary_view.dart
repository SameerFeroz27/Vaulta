import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/loan_provider.dart';
import '../common/empty_state.dart';
import '../common/error_state.dart';
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
            LoanSummaryTable(people: provider.summary),
        ],
      ),
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
