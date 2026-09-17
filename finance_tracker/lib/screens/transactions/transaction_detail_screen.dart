import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../utils/formatters.dart';
import 'transaction_form_screen.dart';

class TransactionDetailScreen extends StatelessWidget {
  final Transaction transaction;

  const TransactionDetailScreen({required this.transaction, super.key});

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final amountColor = t.isExpense
        ? AppTheme.expenseColor
        : AppTheme.incomeColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _openEdit(context),
            tooltip: 'Edit',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context),
            tooltip: 'Delete',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Amount card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    '${t.isExpense ? '-' : '+'}${Formatters.currency(t.amount, code: t.currency)}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StatusChip(status: t.status),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Details card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _DetailRow(
                    label: 'Type',
                    value: t.isExpense ? 'Expense' : 'Income',
                  ),
                  _DetailRow(
                    label: 'Category',
                    value:
                        '${t.categoryIcon ?? '📁'} ${t.categoryName ?? 'Uncategorized'}',
                  ),
                  _DetailRow(label: 'Source', value: t.sourceName),
                  _DetailRow(
                    label: 'Date',
                    value: Formatters.date(t.transactionDate),
                  ),
                  if (t.merchant != null && t.merchant!.isNotEmpty)
                    _DetailRow(label: 'Merchant', value: t.merchant!),
                  if (t.description != null && t.description!.isNotEmpty)
                    _DetailRow(label: 'Description', value: t.description!),
                  if (t.cardLast4 != null)
                    _DetailRow(label: 'Card', value: '**** ${t.cardLast4}'),
                  if (t.bankReference != null)
                    _DetailRow(label: 'Bank Ref', value: t.bankReference!),
                ],
              ),
            ),
          ),

        ],
      ),
    );
  }

  void _openEdit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionFormScreen(transaction: transaction),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = context.read<TransactionProvider>();
              await provider.deleteTransaction(transaction.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'confirmed' => ('Confirmed', AppTheme.incomeColor),
      'needs_review' => ('Needs Review', Colors.orange),
      'archived' => ('Archived', Colors.grey),
      _ => (status, Colors.grey),
    };

    return Chip(
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
