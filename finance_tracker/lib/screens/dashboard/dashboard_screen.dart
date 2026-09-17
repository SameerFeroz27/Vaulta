import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/dashboard_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/dashboard/expense_bar_chart.dart';
import '../../widgets/dashboard/expense_pie_chart.dart';
import '../../widgets/dashboard/summary_card.dart';
import '../transactions/transaction_form_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DashboardProvider>();
    final userCurrency =
        context.watch<AuthProvider>().user?.currency ?? 'PKR';

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: provider.loadDashboard,
        child: _buildBody(provider, userCurrency),
      ),
    );
  }

  Widget _buildBody(DashboardProvider provider, String userCurrency) {
    if (provider.isLoading && provider.summary == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && provider.summary == null) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Center(
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  provider.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: provider.loadDashboard,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final summary = provider.summary;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Month selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: provider.previousMonth,
              ),
              Text(
                Formatters.month(provider.month),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: provider.nextMonth,
              ),
            ],
          ),
        ),

        if (summary != null) ...[
          // Empty state for new users with no transactions
          if (summary.transactionCount == 0) ...[
            const SizedBox(height: 40),
            EmptyState(
              icon: Icons.insights_outlined,
              title: 'Welcome to your dashboard',
              subtitle: 'Add your first transaction to see spending insights, charts, and budgets here.',
              action: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TransactionFormScreen(),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Transaction'),
              ),
            ),
          ] else ...[
            // Summary cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: SummaryCard(
                      label: 'Income',
                      amount: summary.totalIncome,
                      color: AppTheme.incomeColor,
                      icon: Icons.arrow_upward,
                      currency: userCurrency,
                    ),
                  ),
                  Expanded(
                    child: SummaryCard(
                      label: 'Expense',
                      amount: summary.totalExpense,
                      color: AppTheme.expenseColor,
                      icon: Icons.arrow_downward,
                      currency: userCurrency,
                    ),
                  ),
                  Expanded(
                    child: SummaryCard(
                      label: 'Balance',
                      amount: summary.balance,
                      color: const Color(0xFF1976D2),
                      icon: Icons.account_balance_wallet_outlined,
                      currency: userCurrency,
                    ),
                  ),
                ],
              ),
            ),

            // Transaction count
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: Text(
                  '${summary.transactionCount} transactions',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Expense by Category
            if (provider.categoryBreakdown != null)
              ExpensePieChart(
                title: 'Expenses by Category',
                breakdown: provider.categoryBreakdown!,
                currency: userCurrency,
              ),

            // Expense by Source
            if (provider.sourceBreakdown != null)
              ExpensePieChart(
                title: 'Expenses by Source',
                breakdown: provider.sourceBreakdown!,
                currency: userCurrency,
              ),

            // Expense Trend
            if (provider.trend != null && provider.trend!.data.isNotEmpty)
              ExpenseBarChart(trend: provider.trend!),

            // Top Merchants
            if (summary.topMerchants.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Top Merchants',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...summary.topMerchants.map(
                        (m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  m.merchant,
                                  style: const TextStyle(fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                Formatters.currency(m.totalSpent,
                                    code: userCurrency),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.expenseColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }
}
