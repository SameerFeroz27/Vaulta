import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../utils/formatters.dart';

class TransactionFormScreen extends StatefulWidget {
  final Transaction? transaction;

  const TransactionFormScreen({this.transaction, super.key});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _descriptionController = TextEditingController();

  late String _type;
  int? _sourceId;
  int? _categoryId;
  late DateTime _date;
  bool _saving = false;

  bool get _isEdit => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final t = widget.transaction;
    _type = t?.type ?? 'expense';
    _sourceId = t?.sourceId;
    _categoryId = t?.categoryId;
    _date = t != null ? DateTime.parse(t.transactionDate) : DateTime.now();
    if (t != null) {
      _amountController.text = t.amount.toStringAsFixed(2);
      _merchantController.text = t.merchant ?? '';
      _descriptionController.text = t.description ?? '';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().loadCategories();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_sourceId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a source')));
      return;
    }

    setState(() => _saving = true);

    final userCurrency =
        context.read<AuthProvider>().user?.currency ?? 'PKR';

    final body = <String, dynamic>{
      'sourceId': _sourceId,
      'amount': double.parse(_amountController.text),
      'type': _type,
      'currency': userCurrency,
      'transactionDate':
          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
    };
    if (_categoryId != null) body['categoryId'] = _categoryId;
    if (_merchantController.text.trim().isNotEmpty) {
      body['merchant'] = _merchantController.text.trim();
    }
    if (_descriptionController.text.trim().isNotEmpty) {
      body['description'] = _descriptionController.text.trim();
    }

    final provider = context.read<TransactionProvider>();
    bool success;
    if (_isEdit) {
      success = await provider.updateTransaction(widget.transaction!.id, body);
    } else {
      success = await provider.createTransaction(body);
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to save'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryProvider = context.watch<CategoryProvider>();
    final categories = categoryProvider.forType(_type);
    final userCurrency =
        context.watch<AuthProvider>().user?.currency ?? 'PKR';
    final currencySymbol = Constants.currencySymbol(userCurrency);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Transaction' : 'Add Transaction'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Type toggle
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
              ],
              selected: {_type},
              onSelectionChanged: (set) => setState(() {
                _type = set.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: 16),

            // Amount
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '$currencySymbol ',
                isDense: true,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
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

            // Source
            DropdownButtonFormField<int>(
              initialValue: _sourceId,
              decoration: const InputDecoration(
                labelText: 'Source',
                isDense: true,
              ),
              items: Constants.sources
                  .map(
                    (s) => DropdownMenuItem(value: s.id, child: Text(s.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _sourceId = v),
              validator: (value) =>
                  value == null ? 'Please select a source' : null,
            ),
            const SizedBox(height: 16),

            // Category
            DropdownButtonFormField<int?>(
              key: ValueKey('category-$_type'),
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Uncategorized'),
                ),
                ...categories.map(
                  (c) => DropdownMenuItem(
                    value: c.id,
                    child: Text('${c.icon} ${c.name}'),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 16),

            // Date
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  isDense: true,
                  suffixIcon: Icon(Icons.calendar_today_outlined, size: 20),
                ),
                child: Text(
                  Formatters.date(
                    '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Merchant
            TextFormField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: 'Merchant',
                isDense: true,
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                isDense: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Save button
            ElevatedButton(
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
                  : Text(_isEdit ? 'Update' : 'Add Transaction'),
            ),
          ],
        ),
      ),
    );
  }
}
