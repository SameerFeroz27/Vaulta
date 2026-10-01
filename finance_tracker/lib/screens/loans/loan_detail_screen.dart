import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/loan.dart';
import '../../providers/loan_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/loans/record_payment_sheet.dart';
import 'loan_form_screen.dart';

/// One loan in full: what is still owed, how far along, and every repayment made.
class LoanDetailScreen extends StatefulWidget {
  final int loanId;

  const LoanDetailScreen({required this.loanId, super.key});

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  Loan? _loan;
  List<LoanPayment> _payments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await context.read<LoanProvider>().getLoanDetail(widget.loanId);

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result == null) {
        _error = context.read<LoanProvider>().error ?? 'Failed to load this loan';
      } else {
        _loan = result.loan;
        _payments = result.payments;
      }
    });
  }

  Future<void> _recordPayment() async {
    final loan = _loan;
    if (loan == null) return;

    final outcome = await RecordPaymentSheet.show(context, loan);
    if (outcome == null || !mounted) return;

    await _load();
    if (!mounted) return;

    // Kept to the outcome: the sheet already warned about any overpayment, and the
    // card above shows the surplus.
    final message = outcome.alreadyRecorded
        ? 'Already recorded.'
        : outcome.surplusAdded > 0
            ? 'Payment recorded — ${Formatters.currency(outcome.surplusAdded)} over the amount.'
            : outcome.settled
                ? 'Payment recorded — loan settled.'
                : 'Payment recorded.';

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit() async {
    final loan = _loan;
    if (loan == null) return;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoanFormScreen(loan: loan)),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _deleteLoan() async {
    final loan = _loan;
    if (loan == null) return;

    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Remove this loan?',
      message:
          'It disappears from your loans list.\n\n'
          'The ${Formatters.currency(loan.principal)} loan and any cash movements it created '
          'in your transactions are deleted. Repayment records are kept, so '
          '${loan.counterparty} still shows what they repaid in your summary.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;

    final ok = await context.read<LoanProvider>().deleteLoan(loan.id);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to remove the loan'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deletePayment(LoanPayment payment) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete this repayment?',
      message:
          '${Formatters.currency(payment.amount)} on ${Formatters.date(payment.paymentDate)} '
          'will be removed, along with the transaction it created. '
          'The balance goes back up.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    final ok = await context
        .read<LoanProvider>()
        .deletePayment(widget.loanId, payment.id);
    if (!mounted) return;

    if (ok) {
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete the repayment'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loan = _loan;

    return Scaffold(
      appBar: AppBar(
        title: Text(loan?.counterparty ?? 'Loan'),
        actions: [
          if (loan != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteLoan,
              tooltip: 'Remove loan',
            ),
          ],
        ],
      ),
      body: _buildBody(loan),
    );
  }

  Widget _buildBody(Loan? loan) {
    if (_loading) return const LoadingIndicator();
    if (loan == null) {
      return ErrorState(message: _error ?? 'Loan not found', onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _heroCard(loan),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: FilledButton.icon(
              onPressed: _recordPayment,
              icon: const Icon(Icons.add),
              label: const Text('Record payment'),
            ),
          ),
          _sectionHeader('Payment history'),
          if (_payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'No repayments yet.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            )
          else
            ..._payments.map(_paymentTile),
        ],
      ),
    );
  }

  Widget _heroCard(Loan loan) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final amountColor = loan.isLent ? Colors.green[700]! : Colors.red[700]!;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  loan.directionLabel,
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                const Spacer(),
                if (loan.overdue)
                  _Chip(label: 'Overdue', color: Colors.red[700]!)
                else if (loan.isSettled)
                  _Chip(label: 'Settled', color: Colors.green[700]!),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              Formatters.currency(loan.outstanding),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: loan.isSettled ? muted : amountColor,
              ),
            ),
            Text(
              loan.isSettled ? 'Nothing outstanding' : 'still outstanding',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: loan.progress,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  loan.isSettled ? Colors.green[600]! : theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${Formatters.currency(loan.paid)} repaid of ${Formatters.currency(loan.principal)}',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            if (loan.hasSurplus) ...[
              const SizedBox(height: 6),
              Text(
                '${Formatters.currency(loan.surplus)} beyond the amount — counted as a gift, tip or refund',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
            const Divider(height: 24),
            _detailRow('Issued', Formatters.date(loan.issueDate)),
            _detailRow(
              'Due',
              loan.dueDate == null ? 'No due date' : Formatters.date(loan.dueDate!),
              valueColor: loan.overdue ? Colors.red[700] : null,
            ),
            if (loan.notes != null && loan.notes!.trim().isNotEmpty)
              _detailRow('Notes', loan.notes!),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(fontSize: 13, color: muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _paymentTile(LoanPayment payment) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.green.withValues(alpha: 0.12),
        child: Icon(Icons.south_west, size: 16, color: Colors.green[700]),
      ),
      title: Text(
        Formatters.currency(payment.amount),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          Formatters.date(payment.paymentDate),
          if (payment.note != null && payment.note!.trim().isNotEmpty) payment.note!,
          if (payment.transactionId != null) 'in transactions',
        ].join(' · '),
        style: TextStyle(fontSize: 12, color: muted),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () => _deletePayment(payment),
        tooltip: 'Delete repayment',
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
