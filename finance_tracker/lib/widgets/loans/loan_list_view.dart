import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/loan.dart';
import '../../providers/loan_provider.dart';
import '../../screens/loans/loan_detail_screen.dart';
import '../common/app_sheet.dart';
import '../common/empty_state.dart';
import '../common/error_state.dart';
import '../motion/open_tile.dart';
import '../motion/stagger.dart';
import 'loan_card.dart';
import 'loan_filter_sheet.dart';

/// The "Loans" tab: the active loan list behind a single Filters control.
///
/// Navigation is left to [LoanListScreen], which owns the app bar and the FAB, so this
/// view stays presentational.
class LoanListView extends StatefulWidget {
  final VoidCallback onAddLoan;
  final void Function(Loan loan) onRecordPayment;

  const LoanListView({
    required this.onAddLoan,
    required this.onRecordPayment,
    super.key,
  });

  @override
  State<LoanListView> createState() => _LoanListViewState();
}

class _LoanListViewState extends State<LoanListView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<LoanProvider>().loadMore();
    }
  }

  Future<void> _openFilters() async {
    final provider = context.read<LoanProvider>();
    final result = await showAppSheet<LoanFilters>(
      context: context,
      builder: (_) => LoanFilterSheet(currentFilters: provider.filters),
    );
    if (result != null && mounted) {
      provider.setFilters(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LoanProvider>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _FiltersChip(
              summary: _filterSummary(provider.filters),
              active: provider.filters.hasActiveFilters,
              onTap: _openFilters,
            ),
          ),
        ),
        Expanded(child: _buildBody(provider)),
      ],
    );
  }

  /// "All · Any" — the two choices that narrow the list most often, so the chip says what
  /// is on without having to be opened.
  String _filterSummary(LoanFilters f) {
    final direction = f.direction == null
        ? 'All'
        : (f.direction == LoanDirection.lent ? 'Owed to me' : 'I owe');
    final state = f.state == null
        ? 'Any'
        : (f.state == LoanState.open ? 'Open' : 'Settled');
    return '$direction · $state';
  }

  Widget _buildBody(LoanProvider provider) {
    if (provider.isLoading && provider.loans.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.loans.isEmpty) {
      return ErrorState(message: provider.error!, onRetry: provider.loadLoans);
    }

    return RefreshIndicator(
      onRefresh: provider.loadLoans,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 4, bottom: 80),
        children: [
          // Kept inside the list so pull-to-refresh works from the empty state too.
          if (provider.loans.isEmpty)
            SizedBox(height: 280, child: _buildEmptyState(provider))
          else
            for (var i = 0; i < provider.loans.length; i++)
              StaggerItem(index: i, child: _openableLoan(provider.loans[i])),
          if (provider.hasMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
    );
  }

  /// The card grows into its own detail, and the list refreshes once it closes in case a
  /// repayment was recorded there.
  Widget _openableLoan(Loan loan) {
    return OpenTile(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      tileBuilder: (context, open) => LoanCard(
        loan: loan,
        margin: EdgeInsets.zero,
        onTap: open,
        onRecordPayment: () => widget.onRecordPayment(loan),
      ),
      detailBuilder: (_) => LoanDetailScreen(loanId: loan.id),
      onClosed: () => context.read<LoanProvider>().loadLoans(),
    );
  }

  /// "No loans" and "none match this filter" are different problems, so they get
  /// different copy — and only the filtered case offers a way out.
  Widget _buildEmptyState(LoanProvider provider) {
    final filtered = provider.filters.hasActiveFilters;

    return EmptyState(
      icon: Icons.handshake_outlined,
      title: filtered ? 'No loans match these filters' : 'No loans yet',
      subtitle: filtered
          ? 'Try a different person, status, or direction.'
          : 'Record money you have lent to or borrowed from someone.',
      action: filtered
          ? TextButton(
              onPressed: provider.clearFilters,
              child: const Text('Clear filters'),
            )
          : FilledButton.icon(
              onPressed: widget.onAddLoan,
              icon: const Icon(Icons.add),
              label: const Text('Add a loan'),
            ),
    );
  }
}

/// The one control that narrows the loan list — Person, Direction, Status and Sort all live
/// in the sheet behind it, rather than half here and half on the app bar.
class _FiltersChip extends StatelessWidget {
  final String summary;
  final bool active;
  final VoidCallback onTap;

  const _FiltersChip({
    required this.summary,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
          decoration: BoxDecoration(
            border: Border.all(
              color: active ? scheme.primary : theme.dividerColor,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list, size: 18, color: muted),
              const SizedBox(width: 7),
              const Text(
                'Filters',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(summary, style: TextStyle(fontSize: 12, color: muted)),
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 18, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
