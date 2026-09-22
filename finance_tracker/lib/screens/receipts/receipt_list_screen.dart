import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/receipt.dart';
import '../../providers/auth_provider.dart';
import '../../providers/receipt_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_indicator.dart';

/// Lists the user's scan history (receipts and bank messages) with
/// status badges. Scanning is done from the Transactions page.
class ReceiptListScreen extends StatefulWidget {
  const ReceiptListScreen({super.key});

  @override
  State<ReceiptListScreen> createState() => _ReceiptListScreenState();
}

class _ReceiptListScreenState extends State<ReceiptListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReceiptProvider>().loadReceipts(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan History')),
      body: Consumer<ReceiptProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.receipts.isEmpty) {
            return const LoadingIndicator();
          }
          if (provider.error != null && provider.receipts.isEmpty) {
            return ErrorState(
              message: provider.error!,
              onRetry: () => provider.loadReceipts(force: true),
            );
          }
          if (provider.receipts.isEmpty) {
            return const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No scans yet',
              subtitle:
                  'Use the scan icon on the Transactions page to scan a receipt.',
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadReceipts(force: true),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: provider.receipts.length,
              itemBuilder: (context, index) {
                final receipt = provider.receipts[index];
                return _ReceiptTile(
                  receipt: receipt,
                  currency: context.read<AuthProvider>().user?.currency ??
                      'PKR',
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  final Receipt receipt;
  final String currency;

  const _ReceiptTile({required this.receipt, this.currency = 'PKR'});

  IconData get _icon => switch (receipt.inputType) {
    'image' => Icons.money_outlined,
    'bank_message' => Icons.credit_card_outlined,
    'virtual_receipt' => Icons.wifi_outlined,
    _ => Icons.receipt_outlined,
  };

  String get _typeLabel => switch (receipt.inputType) {
    'image' => 'Cash',
    'bank_message' => 'Card',
    'virtual_receipt' => 'Online',
    _ => receipt.inputType,
  };

  @override
  Widget build(BuildContext context) {
    final hasAmount = receipt.amount != null;
    final isIncome = receipt.transactionType == 'income';

    return Card(
      child: ListTile(
        leading: Icon(_icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        title: Text(
          _typeLabel,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          [
            if (receipt.merchant != null) receipt.merchant!,
            Formatters.shortDate(receipt.createdAt),
          ].join(' • '),
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasAmount) ...[
              Text(
                '${isIncome ? '+' : '-'}${Formatters.currency(double.tryParse(receipt.amount!) ?? 0, code: currency)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isIncome
                      ? const Color(0xFF43A047)
                      : const Color(0xFFE53935),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
            ],
            _statusBadge(receipt.status),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final Color color;
    final String label;
    switch (status) {
      case 'queued':
        color = const Color(0xFF1976D2);
        label = 'Queued';
      case 'processing':
        color = const Color(0xFF1976D2);
        label = 'Processing';
      case 'success':
        color = const Color(0xFF43A047);
        label = 'Completed';
      case 'needs_review':
        color = const Color(0xFFFF9800);
        label = 'Review';
      case 'failed':
        color = const Color(0xFFE53935);
        label = 'Failed';
      case 'duplicate':
        color = Colors.grey;
        label = 'Duplicate';
      default:
        color = Colors.grey;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
