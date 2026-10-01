import 'package:flutter/foundation.dart';

import '../models/dashboard_summary.dart';
import '../models/expense_breakdown.dart';
import '../models/expense_trend.dart';
import '../services/api_client.dart';
import '../services/dashboard_service.dart';
import '../utils/formatters.dart';

/// Manages dashboard data for the selected month.
class DashboardProvider extends ChangeNotifier {
  final DashboardService _dashboardService;

  DashboardProvider({required ApiClient apiClient})
    : _dashboardService = DashboardService(apiClient: apiClient);

  String _month = Formatters.currentMonth();
  DashboardSummary? _summary;
  ExpenseBreakdown? _categoryBreakdown;
  ExpenseBreakdown? _sourceBreakdown;
  ExpenseTrend? _trend;
  bool _isLoading = false;
  String? _error;

  String get month => _month;
  DashboardSummary? get summary => _summary;
  ExpenseBreakdown? get categoryBreakdown => _categoryBreakdown;
  ExpenseBreakdown? get sourceBreakdown => _sourceBreakdown;
  ExpenseTrend? get trend => _trend;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load all dashboard data for the current month in parallel.
  Future<void> loadDashboard() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _dashboardService.summary(_month),
        _dashboardService.expenseByCategory(_month),
        _dashboardService.expenseBySource(_month),
        _dashboardService.expenseTrend(),
      ]);

      _summary = results[0] as DashboardSummary;
      _categoryBreakdown = results[1] as ExpenseBreakdown;
      _sourceBreakdown = results[2] as ExpenseBreakdown;
      _trend = results[3] as ExpenseTrend;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  void previousMonth() {
    _month = Formatters.shiftMonth(_month, -1);
    loadDashboard();
  }

  void nextMonth() {
    _month = Formatters.shiftMonth(_month, 1);
    loadDashboard();
  }

  void currentMonth() {
    _month = Formatters.currentMonth();
    loadDashboard();
  }

  /// Clear all cached state — called on login/register/logout.
  void reset() {
    _month = Formatters.currentMonth();
    _summary = null;
    _categoryBreakdown = null;
    _sourceBreakdown = null;
    _trend = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
