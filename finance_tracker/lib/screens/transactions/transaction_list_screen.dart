import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/app_sheet.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/motion/full_motion_route.dart';
import '../../widgets/motion/open_tile.dart';
import '../../widgets/motion/stagger.dart';
import '../../widgets/transactions/review_sheet.dart';
import '../../widgets/transactions/transaction_card.dart';
import '../../widgets/transactions/transaction_filter_sheet.dart';
import 'transaction_detail_screen.dart';
import 'transaction_form_screen.dart';
import '../receipts/receipt_scan_screen.dart';

/// Marks where a day's group begins in the flattened list.
class _DayHeading {
  final String date;

  const _DayHeading(this.date);
}

class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.text = context.read<TransactionProvider>().filters.search ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<TransactionProvider>();
      if (provider.transactions.isEmpty && !provider.isLoading) {
        provider.loadTransactions();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
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
    final result = await showAppSheet<TransactionFilters>(
      context: context,
      builder: (_) => TransactionFilterSheet(currentFilters: provider.filters),
    );
    if (result != null && mounted) {
      provider.setFilters(result);
    }
  }

  void _openForm() {
    Navigator.of(context)
        .push(FullMotionPageRoute(builder: (_) => const TransactionFormScreen()));
  }

  void _openScanner() {
    Navigator.of(context)
        .push(FullMotionPageRoute(builder: (_) => const ReceiptScanScreen()));
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
    final Widget content;

    if (provider.isLoading && provider.transactions.isEmpty) {
      content = const LoadingIndicator();
    } else if (provider.error != null && provider.transactions.isEmpty) {
      content = ErrorState(
        message: provider.error!,
        onRetry: provider.loadTransactions,
      );
    } else if (provider.transactions.isEmpty) {
      content = _buildEmptyState(provider);
    } else {
      content = RefreshIndicator(
        onRefresh: provider.loadTransactions,
        child: _buildList(provider),
      );
    }

    return Column(
      children: [
        _buildSearchField(provider),
        if (_showReviewBanner(provider)) _buildReviewBanner(provider),
        Expanded(child: content),
      ],
    );
  }

  /// Inline search, so the list can be narrowed without opening the filter sheet. Debounced
  /// so a fast typist does not fire a request per keystroke.
  Widget _buildSearchField(TransactionProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search merchant, note or amount',
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: provider.filters.search == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    context.read<TransactionProvider>().setSearch(null);
                  },
                ),
        ),
        onChanged: (value) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 350), () {
            if (!mounted) return;
            context.read<TransactionProvider>().setSearch(value);
          });
        },
      ),
    );
  }

  /// The list, flattened into day headings and rows.
  ///
  /// Headings only appear when the list is date-sorted: under an amount sort the days
  /// interleave, and a heading per run of rows would read as a duplicate.
  Widget _buildList(TransactionProvider provider) {
    final groupByDay = provider.filters.sort == 'date';
    final rows = <Object>[];
    // The transaction ordinal, parallel to [rows], so the stagger counts rows rather than
    // day headings. Headings carry -1.
    final ordinals = <int>[];
    String? lastDate;
    var ordinal = 0;

    for (final t in provider.transactions) {
      if (groupByDay && t.transactionDate != lastDate) {
        rows.add(_DayHeading(t.transactionDate));
        ordinals.add(-1);
        lastDate = t.transactionDate;
      }
      rows.add(t);
      ordinals.add(ordinal++);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: rows.length + (provider.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == rows.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final row = rows[index];
        if (row is _DayHeading) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              Formatters.dayLabel(row.date),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        final t = row as Transaction;
        return StaggerItem(
          index: ordinals[index],
          child: _openableTransaction(t),
        );
      },
    );
  }

  /// The row grows into the transaction's detail, starting from the row itself.
  Widget _openableTransaction(Transaction t) {
    return OpenTile(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      tileBuilder: (context, open) => TransactionCard(
        transaction: t,
        margin: EdgeInsets.zero,
        onTap: open,
      ),
      detailBuilder: (_) => TransactionDetailScreen(transaction: t),
    );
  }

  /// Makes the review queue reachable in one tap — otherwise held-back transactions
  /// accumulate invisibly, since they are excluded from dashboard totals.
  bool _showReviewBanner(TransactionProvider provider) =>
      provider.pendingReviewCount > 0 &&
      provider.filters.status != 'needs_review';
  Widget _buildReviewBanner(TransactionProvider provider) {
    final count = provider.pendingReviewCount;
    return Material(
      color: Colors.orange.withValues(alpha: 0.12),
      child: InkWell(
        // The decision is small, so it stays a sheet rather than taking over the screen.
        onTap: () => ReviewSheet.show(context),
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
