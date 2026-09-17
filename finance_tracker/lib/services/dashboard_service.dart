import '../models/budget_status.dart';
import '../models/dashboard_summary.dart';
import '../models/expense_breakdown.dart';
import '../models/expense_trend.dart';
import 'api_client.dart';

/// Handles dashboard analytics API calls.
class DashboardService {
  final ApiClient apiClient;

  DashboardService({required this.apiClient});

  Future<DashboardSummary> summary(String month) async {
    final data = await apiClient.get(
      '/dashboard/summary',
      query: {'month': month},
    );
    return DashboardSummary.fromJson(data);
  }

  Future<ExpenseBreakdown> expenseByCategory(String month) async {
    final data = await apiClient.get(
      '/dashboard/expense-by-category',
      query: {'month': month},
    );
    return ExpenseBreakdown.fromJson(data, 'categories');
  }

  Future<ExpenseBreakdown> expenseBySource(String month) async {
    final data = await apiClient.get(
      '/dashboard/expense-by-source',
      query: {'month': month},
    );
    return ExpenseBreakdown.fromJson(data, 'sources');
  }

  Future<ExpenseTrend> expenseTrend({int months = 6}) async {
    final data = await apiClient.get(
      '/dashboard/expense-trend',
      query: {'months': months},
    );
    return ExpenseTrend.fromJson(data);
  }

  Future<BudgetStatus> budgetStatus(String month) async {
    final data = await apiClient.get(
      '/dashboard/budget-status',
      query: {'month': month},
    );
    return BudgetStatus.fromJson(data);
  }
}
