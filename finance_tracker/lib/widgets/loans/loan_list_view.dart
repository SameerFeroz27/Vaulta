import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/loan.dart';
import '../../providers/loan_provider.dart';
import '../common/empty_state.dart';
import '../common/error_state.dart';
import 'loan_card.dart';

/// The "Loans" tab: the active loan list with its direction filter.
///
/// Navigation is left to [LoanListScreen], which owns the app bar and the FAB, so this
/// view stays presentational.
class LoanListView extends StatefulWidget {
  final VoidCallback onAddLoan;
  final void Function(Loan loan) onOpenLoan;

  const LoanListView({
    required this.onAddLoan,
    required this.onOpenLoan,
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

  /// 'all' | 'lent' | 'borrowed'. Kept out of [LoanFilters] so the sheet and this
  /// segmented control can be changed independently.
  String get _directionFilter {
    final direction = context.watch<LoanProvider>().filters.direction;
    return direction ?? 'all';
  }

  void _applyDirection(String value) {
    final provider = context.read<LoanProvider>();
    final f = provider.filters;
    provider.setFilters(
      LoanFilters(
        direction: value == 'all' ? null : value,
        state: f.state,
        search: f.search,
        sort: f.sort,
        order: f.order,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LoanProvider>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: LoanDirection.lent, label: Text('Owed to me')),
              ButtonSegment(value: LoanDirection.borrowed, label: Text('I owe')),
            ],
            selected: {_directionFilter},
            onSelectionChanged: (set) => _applyDirection(set.first),
          ),
        ),
        Expanded(child: _buildBody(provider)),
      ],
    );
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
            ...provider.loans.map(
              (loan) => LoanCard(
                loan: loan,
                onTap: () => widget.onOpenLoan(loan),
              ),
            ),
          if (provider.hasMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
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
