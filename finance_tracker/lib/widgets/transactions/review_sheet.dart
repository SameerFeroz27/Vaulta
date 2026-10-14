import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/transaction.dart';
import '../../providers/transaction_provider.dart';
import '../../utils/formatters.dart';
import '../common/app_sheet.dart';

/// The quick decision behind the review banner's Show: the rows waiting on a direction,
/// with the one action that clears them all. A decision this small stays a sheet, never a
/// full screen.
class ReviewSheet extends StatefulWidget {
  const ReviewSheet({super.key});

  static Future<void> show(BuildContext context) =>
      showAppSheet<void>(context: context, builder: (_) => const ReviewSheet());

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  /// Null while the rows are still loading.
  List<Transaction>? _pending;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await context.read<TransactionProvider>().fetchPendingReview();
    if (mounted) setState(() => _pending = rows);
  }

  Future<void> _markAllReviewed() async {
    setState(() => _busy = true);
    final provider = context.read<TransactionProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final count = await provider.markAllAsReviewed();
    if (!mounted) return;

    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count == 1
              ? '1 transaction marked as reviewed.'
              : '$count transactions marked as reviewed.',
        ),
      ),
    );
  }

  /// Hands the user off to the list filtered to the same rows, where each can be opened and
  /// its direction changed individually.
  void _reviewIndividually() {
    final provider = context.read<TransactionProvider>();
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
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final pending = _pending;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Needs review', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'The direction could not be settled, so these are held out of your dashboard '
              'totals until you decide.',
              style: TextStyle(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 12),

            if (pending == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (pending.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nothing is waiting on a decision.',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              )
            else
              for (final t in pending) _ReviewRow(transaction: t),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || pending == null || pending.isEmpty
                        ? null
                        : _reviewIndividually,
                    child: const Text('Review one by one'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        _busy || pending == null || pending.isEmpty
                            ? null
                            : _markAllReviewed,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Mark as reviewed'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final Transaction transaction;

  const _ReviewRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final color = t.isExpense
        ? AppTheme.expenseFor(context)
        : AppTheme.incomeFor(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Text(t.categoryIcon ?? '📁', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t.merchant ?? t.categoryName ?? 'Transaction',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${t.isExpense ? '-' : '+'}${Formatters.currency(t.amount, code: t.currency)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
