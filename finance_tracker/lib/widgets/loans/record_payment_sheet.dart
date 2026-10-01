import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/loan.dart';
import '../../providers/loan_provider.dart';
import '../../utils/formatters.dart';

/// What happened when the sheet closed, so the caller can report it accurately.
class RecordPaymentOutcome {
  final bool alreadyRecorded;
  final bool settled;
  final double surplusAdded;

  RecordPaymentOutcome({
    this.alreadyRecorded = false,
    this.settled = false,
    this.surplusAdded = 0,
  });
}

/// Bottom sheet for recording a repayment against a loan.
///
/// Returns a [RecordPaymentOutcome] when the sheet closed after a save attempt,
/// or null when the user cancelled.
class RecordPaymentSheet extends StatefulWidget {
  final Loan loan;

  const RecordPaymentSheet({required this.loan, super.key});

  static Future<RecordPaymentOutcome?> show(BuildContext context, Loan loan) {
    return showModalBottomSheet<RecordPaymentOutcome>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordPaymentSheet(loan: loan),
    );
  }

  @override
  State<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late DateTime _date;
  bool _recordTransaction = true;
  bool _saving = false;

  /// Generated once per sheet and reused on retry, so a double tap on "Record"
  /// cannot produce two repayments — the backend rejects the second as a conflict.
  late final String _idempotencyKey;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    if (widget.loan.outstanding > 0) {
      _amountController.text = widget.loan.outstanding.toStringAsFixed(2);
    }
    _idempotencyKey =
        'loan-payment-${widget.loan.id}-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_amountController.text) ?? 0;
  double get _overpayBy {
    final over = _amount - widget.loan.outstanding;
    return over > 0 ? over : 0;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _date = picked);
  }

  String get _dateString => Formatters.toDateString(_date);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final body = <String, dynamic>{
      'amount': _amount,
      'paymentDate': _dateString,
      'recordTransaction': _recordTransaction,
      'idempotencyKey': _idempotencyKey,
    };
    if (_noteController.text.trim().isNotEmpty) {
      body['note'] = _noteController.text.trim();
    }

    final provider = context.read<LoanProvider>();
    final result = await provider.addPayment(widget.loan.id, body);
    if (!mounted) return;
    setState(() => _saving = false);

    if (result != null) {
      Navigator.of(context).pop(
        RecordPaymentOutcome(
          settled: result.settled,
          surplusAdded: result.surplusAdded,
        ),
      );
      return;
    }

    // A conflict means this exact payment is already recorded — that is the
    // double-tap being absorbed, not a failure worth alarming the user about.
    if (provider.errorCode == 'CONFLICT') {
      Navigator.of(context).pop(RecordPaymentOutcome(alreadyRecorded: true));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(provider.error ?? 'Failed to record payment'),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final symbol = 'PKR';

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Record payment', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                '${widget.loan.counterparty} · ${Formatters.currency(widget.loan.outstanding)} outstanding',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₨ ',
                  isDense: true,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Amount is required';
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'Enter a valid amount greater than 0';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),

              // Overpaying is accepted rather than blocked, so say up front where
              // the extra lands instead of letting it surprise them afterwards.
              if (_overpayBy > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${Formatters.currency(_overpayBy)} more than is owed — '
                          'the extra counts as a gift, tip or refund.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Payment date',
                    isDense: true,
                    suffixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                  ),
                  child: Text(Formatters.date(_dateString)),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Note', isDense: true),
                maxLines: 2,
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _recordTransaction,
                onChanged: (v) => setState(() => _recordTransaction = v),
                title: const Text('Also record in my transactions', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  'Keeps the cash movement in your ledger. It never counts as income or expense.',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
              const SizedBox(height: 16),

              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Record payment'),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  symbol == 'PKR' ? 'Loans are tracked in PKR' : symbol,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
