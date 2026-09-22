import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../models/budget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/category_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/confirm_dialog.dart';

/// Form for creating or editing a budget.
///
/// Pass a [budget] to edit an existing budget; omit it to create a new one.
class BudgetFormScreen extends StatefulWidget {
  final Budget? budget;

  const BudgetFormScreen({super.key, this.budget});

  @override
  State<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends State<BudgetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late String _selectedMonth;
  late int _categoryValue; // -1 = overall budget
  bool _isSaving = false;

  bool get _isEditing => widget.budget != null;

  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    _amountController = TextEditingController(
      text: b != null ? b.amount.toStringAsFixed(2) : '',
    );
    _selectedMonth = b?.month ?? Formatters.currentMonth();
    _categoryValue = b?.categoryId ?? -1;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String _shiftMonth(String month, int delta) {
    final parts = month.split('-');
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final shifted = DateTime(date.year, date.month + delta);
    return '${shifted.year}-${shifted.month.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final provider = context.read<BudgetProvider>();
    final amount = double.parse(_amountController.text.trim());
    final categoryId = _categoryValue == -1 ? null : _categoryValue;

    try {
      if (_isEditing) {
        await provider.updateBudget(
          widget.budget!.id,
          amount: amount,
          month: _selectedMonth,
          categoryId: categoryId,
        );
      } else {
        await provider.createBudget(
          amount: amount,
          month: _selectedMonth,
          categoryId: categoryId,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_extractErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final provider = context.read<BudgetProvider>();
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete budget?',
      message:
          'This budget for ${Formatters.month(_selectedMonth)} will be removed.',
    );
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _isSaving = true);

    try {
      await provider.deleteBudget(widget.budget!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _extractErrorMessage(Object error) {
    final str = error.toString();
    if (str.contains('CONFLICT')) {
      return 'A budget for this category and month already exists.';
    }
    return str.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final userCurrency =
        context.watch<AuthProvider>().user?.currency ?? 'PKR';
    final currencySymbol = Constants.currencySymbol(userCurrency);

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Budget' : 'New Budget')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Amount
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Budget Amount',
                hintText: 'e.g. 50000',
                prefixText: '$currencySymbol ',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Amount is required';
                }
                final parsed = double.tryParse(value.trim());
                if (parsed == null || parsed <= 0) {
                  return 'Enter a valid positive amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Month selector
            Text(
              'Month',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(
                    () => _selectedMonth = _shiftMonth(_selectedMonth, -1),
                  ),
                ),
                Text(
                  Formatters.month(_selectedMonth),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(
                    () => _selectedMonth = _shiftMonth(_selectedMonth, 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Category
            Text(
              'Category',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Consumer<CategoryProvider>(
              builder: (context, catProvider, _) {
                final expenseCategories = catProvider.forType('expense');
                return DropdownButtonFormField<int>(
                  initialValue: _categoryValue,
                  decoration: const InputDecoration(
                    hintText: 'Select category',
                  ),
                  items: [
                    const DropdownMenuItem<int>(
                      value: -1,
                      child: Text('Overall Budget'),
                    ),
                    ...expenseCategories.map(
                      (c) => DropdownMenuItem<int>(
                        value: c.id,
                        child: Text('${c.icon}  ${c.name}'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _categoryValue = value);
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 32),

            // Save
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isEditing ? 'Update' : 'Create'),
            ),

            // Delete (edit mode only)
            if (_isEditing) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isSaving ? null : _delete,
                style: TextButton.styleFrom(foregroundColor: Colors.red[700]),
                child: const Text('Delete Budget'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
