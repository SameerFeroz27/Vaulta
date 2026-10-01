import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/transactions/transaction_card.dart';
import '../../widgets/transactions/transaction_filter_sheet.dart';
import 'transaction_detail_screen.dart';
import 'transaction_form_screen.dart';
import '../receipts/receipt_scan_screen.dart';

class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<TransactionProvider>();
      if (provider.transactions.isEmpty && !provider.isLoading) {
        provider.loadTransactions();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<TransactionProvider>().loadMore();
    }
  }

  void _openFilters() async {
    final provider = context.read<TransactionProvider>();
    final result = await showModalBottomSheet<TransactionFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TransactionFilterSheet(currentFilters: provider.filters),
    );
    if (result != null && mounted) {
      provider.setFilters(result);
    }
  }

  void _openDetail(Transaction transaction) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionDetailScreen(transaction: transaction),
      ),
    );
  }

  void _openForm() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TransactionFormScreen()));
  }

  void _openScanner() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ReceiptScanScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: _openScanner,
            tooltip: 'Scan Receipt',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list_outlined),
            onPressed: _openFilters,
            tooltip: 'Filters',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
      body: _buildBody(provider),
    );
  }

  Widget _buildBody(TransactionProvider provider) {
    if (provider.isLoading && provider.transactions.isEmpty) {
      return const LoadingIndicator();
    }

    if (provider.error != null && provider.transactions.isEmpty) {
      return ErrorState(
        message: provider.error!,
        onRetry: provider.loadTransactions,
      );
    }

    final content = provider.transactions.isEmpty
        ? _buildEmptyState(provider)
        : RefreshIndicator(
            onRefresh: provider.loadTransactions,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 80),
              itemCount:
                  provider.transactions.length + (provider.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == provider.transactions.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final t = provider.transactions[index];
                return TransactionCard(
                  transaction: t,
                  onTap: () => _openDetail(t),
                );
              },
            ),
          );

    // Hide the banner once the user is already looking at the review queue.
    final showReviewBanner =
        provider.pendingReviewCount > 0 &&
        provider.filters.status != 'needs_review';

    if (!showReviewBanner) return content;

    return Column(
      children: [
        _buildReviewBanner(provider),
        Expanded(child: content),
      ],
    );
  }

  /// Makes the review queue reachable in one tap — otherwise held-back transactions
  /// accumulate invisibly, since they are excluded from dashboard totals.
  Widget _buildReviewBanner(TransactionProvider provider) {
    final count = provider.pendingReviewCount;
    return Material(
      color: Colors.orange.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () => _showPendingReview(provider),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.pending_actions_outlined,
                color: Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 transaction needs review'
                      : '$count transactions need review',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Text(
                'Show',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.orange),
            ],
          ),
        ),
      ),
    );
  }

  void _showPendingReview(TransactionProvider provider) {
    final f = provider.filters;
    provider.setFilters(
      TransactionFilters(
        month: f.month,
        source: f.source,
        category: f.category,
        type: f.type,
        search: f.search,
        sort: f.sort,
        order: f.order,
        status: 'needs_review',
      ),
    );
  }

  Widget _buildEmptyState(TransactionProvider provider) {
    final filtered = provider.filters.hasActiveFilters;
    return EmptyState(
      icon: Icons.receipt_long_outlined,
      title: filtered ? 'No transactions match' : 'No transactions yet',
      subtitle: filtered
          ? 'Try adjusting or clearing the filters'
          : 'Tap + to add your first one',
      action: filtered
          ? TextButton(
              onPressed: provider.clearFilters,
              child: const Text('Clear filters'),
            )
          : null,
    );
  }
}
