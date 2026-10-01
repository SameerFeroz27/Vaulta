import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/loan.dart';
import '../../providers/loan_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/button_spinner.dart';

/// Add or edit a loan. Pops `true` when a loan was saved.
class LoanFormScreen extends StatefulWidget {
  final Loan? loan;

  const LoanFormScreen({this.loan, super.key});

  @override
  State<LoanFormScreen> createState() => _LoanFormScreenState();
}

class _LoanFormScreenState extends State<LoanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _personController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  late String _direction;
  late DateTime _issueDate;
  DateTime? _dueDate;
  bool _recordTransaction = true;
  bool _saving = false;

  bool get _isEdit => widget.loan != null;

  @override
  void initState() {
    super.initState();
    final l = widget.loan;
    _direction = l?.direction ?? LoanDirection.lent;
    _issueDate = l != null ? DateTime.parse(l.issueDate) : DateTime.now();
    _dueDate = l?.dueDate == null ? null : DateTime.parse(l!.dueDate!);

    if (l != null) {
      _personController.text = l.counterparty;
      _amountController.text = l.principal.toStringAsFixed(2);
      _notesController.text = l.notes ?? '';
    }
  }

  @override
  void dispose() {
    _personController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickIssueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _issueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _issueDate = picked);
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _issueDate.add(const Duration(days: 30)),
      firstDate: _issueDate,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final body = <String, dynamic>{
      'counterparty': _personController.text.trim(),
      'direction': _direction,
      'principal': double.parse(_amountController.text),
      'issueDate': Formatters.toDateString(_issueDate),
    };

    final notes = _notesController.text.trim();
    if (_isEdit) {
      // Nulls are meaningful here: they clear a due date or notes.
      body['dueDate'] = _dueDate == null
          ? null
          : Formatters.toDateString(_dueDate!);
      body['notes'] = notes.isEmpty ? null : notes;
    } else {
      if (_dueDate != null) {
        body['dueDate'] = Formatters.toDateString(_dueDate!);
      }
      if (notes.isNotEmpty) body['notes'] = notes;
      body['recordTransaction'] = _recordTransaction;
    }

    final provider = context.read<LoanProvider>();
    final success = _isEdit
        ? await provider.updateLoan(widget.loan!.id, body)
        : await provider.createLoan(body);

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to save the loan'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Loan' : 'Add Loan')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: LoanDirection.lent, label: Text('I lent')),
                ButtonSegment(value: LoanDirection.borrowed, label: Text('I borrowed')),
              ],
              selected: {_direction},
              onSelectionChanged: (set) =>
                  setState(() => _direction = set.first),
            ),
            const SizedBox(height: 6),
            Text(
              _direction == LoanDirection.lent
                  ? 'They owe you this amount.'
                  : 'You owe them this amount.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _personController,
              decoration: const InputDecoration(
                labelText: 'Person',
                helperText: 'Capital first letter and a space, e.g. "Sana Malik", '
                    'so the name reads the same everywhere',
                helperMaxLines: 2,
                isDense: true,
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Person is required';
                }
                if (value.trim().length > 100) return 'Name is too long';
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₨ ',
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Amount is required';
                final amount = double.tryParse(value);
                if (amount == null || amount <= 0) {
                  return 'Enter a valid amount greater than 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            InkWell(
              onTap: _pickIssueDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date lent / borrowed',
                  isDense: true,
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                ),
                child: Text(
                  Formatters.date(Formatters.toDateString(_issueDate)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickDueDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Due date',
                        helperText: 'Optional',
                        isDense: true,
                        suffixIcon: Icon(Icons.event_outlined, size: 20),
                      ),
                      child: Text(
                        _dueDate == null
                            ? 'None'
                            : Formatters.date(Formatters.toDateString(_dueDate!)),
                      ),
                    ),
                  ),
                ),
                if (_dueDate != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () => setState(() => _dueDate = null),
                    tooltip: 'Clear due date',
                  ),
              ],
            ),
            const SizedBox(height: 8),

            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes', isDense: true),
              maxLines: 3,
            ),

            // Only offered on create — the money movement is recorded once, when the
            // loan is first entered, and edited from the Transactions tab afterwards.
            if (!_isEdit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _recordTransaction,
                onChanged: (v) => setState(() => _recordTransaction = v),
                title: const Text(
                  'Also record this in my transactions',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  'Keeps the cash movement in your ledger. It never counts as income or expense.',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ),
            const SizedBox(height: 16),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const ButtonSpinner()
                  : Text(_isEdit ? 'Save changes' : 'Add loan'),
            ),
          ],
        ),
      ),
    );
  }
}
