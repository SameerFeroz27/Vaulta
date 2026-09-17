import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
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
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(provider.error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: provider.loadTransactions,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (provider.transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No transactions yet',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add your first one',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.loadTransactions,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: provider.transactions.length + (provider.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == provider.transactions.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
  }
}
