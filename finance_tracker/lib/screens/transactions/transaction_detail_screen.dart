import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../utils/formatters.dart';
import 'transaction_form_screen.dart';
import '../../widgets/motion/full_motion_route.dart';

class TransactionDetailScreen extends StatelessWidget {
  final Transaction transaction;

  const TransactionDetailScreen({required this.transaction, super.key});

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final amountColor = t.isExpense
        ? AppTheme.expenseFor(context)
        : AppTheme.incomeFor(context);

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

          if (t.needsReview) ...[
            _buildReviewCard(context),
            const SizedBox(height: 8),
          ],

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
                  if (t.isAutoClassified)
                    _DetailRow(
                      label: 'Decided by',
                      value: t.typeConfidence == null
                          ? 'AI'
                          : 'AI (${(t.typeConfidence! * 100).round()}% confident)',
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

  /// One-tap resolution of a transaction whose direction the AI could not settle.
  Widget _buildReviewCard(BuildContext context) {
    final t = transaction;

    return Card(
      color: Colors.orange.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.pending_actions_outlined,
                  color: Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Confirm the direction',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Only the consequence the user cannot see elsewhere: the row is held
            // back from their totals. The type is in the rows above.
            Text(
              'Not in your totals until you confirm.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _confirmDirection(context),
                    child: const Text('Confirm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _flipDirection(context),
                    child: Text('Change to ${t.isExpense ? 'Income' : 'Expense'}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDirection(BuildContext context) async {
    final provider = context.read<TransactionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (await provider.confirmTransaction(transaction.id)) {
      navigator.pop();
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not confirm the transaction.')),
      );
    }
  }

  /// Flip income/expense and confirm in one step.
  ///
  /// The category is deliberately left untouched: AI-filed transactions are
  /// uncategorized, and silently clearing a category the user set themselves would
  /// be more surprising than leaving it.
  Future<void> _flipDirection(BuildContext context) async {
    final provider = context.read<TransactionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final newType = transaction.isExpense ? 'income' : 'expense';

    final ok = await provider.updateTransaction(transaction.id, {
      'type': newType,
      'status': 'confirmed',
    });

    if (ok) {
      navigator.pop();
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update the transaction.')),
      );
    }
  }

  void _openEdit(BuildContext context) {
    Navigator.of(context).push(
      FullMotionPageRoute(
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
            width: 90,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
