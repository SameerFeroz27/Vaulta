import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/budget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budget_provider.dart';
import '../../utils/errors.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/confirm_dialog.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/error_state.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/dashboard/budget_progress_card.dart';
import 'budget_form_screen.dart';

/// Lists budgets for the selected month with progress bars.
/// Supports creating, editing, and deleting budgets.
class BudgetListScreen extends StatefulWidget {
  const BudgetListScreen({super.key});

  @override
  State<BudgetListScreen> createState() => _BudgetListScreenState();
}

class _BudgetListScreenState extends State<BudgetListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BudgetProvider>().loadBudgets(force: true);
    });
  }

  void _openForm([Budget? budget]) {
    final provider = context.read<BudgetProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BudgetFormScreen(budget: budget)),
    ).then((_) => provider.loadBudgets(force: true));
  }

  Future<void> _deleteBudget(Budget budget) async {
    final provider = context.read<BudgetProvider>();
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete budget?',
      message:
          'This budget for ${Formatters.month(budget.month)} will be removed.',
    );
    if (!confirmed) return;

    try {
      await provider.deleteBudget(budget.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: Consumer<BudgetProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              _buildMonthSelector(context, provider),
              Expanded(child: _buildBody(context, provider)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMonthSelector(BuildContext context, BudgetProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: provider.previousMonth,
          ),
          Text(
            Formatters.month(provider.selectedMonth),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: provider.nextMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, BudgetProvider provider) {
    if (provider.isLoading && provider.budgets.isEmpty) {
      return const LoadingIndicator();
    }
    if (provider.error != null && provider.budgets.isEmpty) {
      return ErrorState(
        message: provider.error!,
        onRetry: () => provider.loadBudgets(force: true),
      );
    }
    if (provider.budgets.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No budgets for ${Formatters.month(provider.selectedMonth)}',
        subtitle: 'Tap the + button to set a budget.',
        action: FilledButton(
          onPressed: () => _openForm(),
          child: const Text('Add Budget'),
        ),
      );
    }

    final overall = provider.budgets.where((b) => b.isOverall).toList();
    final categoryBudgets = provider.budgets
        .where((b) => !b.isOverall)
        .toList();

    return RefreshIndicator(
      onRefresh: () => provider.loadBudgets(force: true),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          ...overall.map((b) => _buildBudgetCard(context, b)),
          ...categoryBudgets.map((b) => _buildBudgetCard(context, b)),
        ],
      ),
    );
  }

  Widget _buildBudgetCard(BuildContext context, Budget budget) {
    return GestureDetector(
      onTap: () => _openForm(budget),
      onLongPress: () => _deleteBudget(budget),
      child: BudgetProgressCard(
        label: budget.isOverall
            ? 'Overall Budget'
            : budget.categoryName ?? 'Category',
        budgetAmount: budget.amount,
        spent: budget.spent,
        percentage: budget.percentage,
        overBudget: budget.overBudget,
        icon: budget.categoryIcon,
        colorHex: budget.categoryColor,
        currency:
            context.read<AuthProvider>().user?.currency ?? 'PKR',
      ),
    );
  }
}
