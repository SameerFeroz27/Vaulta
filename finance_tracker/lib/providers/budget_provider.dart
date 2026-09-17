import 'package:flutter/foundation.dart';

import '../models/budget.dart';
import '../models/transaction.dart' show Pagination;
import '../services/api_client.dart';
import '../services/budget_service.dart';
import '../utils/formatters.dart';

/// Manages the budget list with month navigation.
class BudgetProvider extends ChangeNotifier {
  final BudgetService _budgetService;

  BudgetProvider({required ApiClient apiClient})
    : _budgetService = BudgetService(apiClient: apiClient);

  List<Budget> _budgets = [];
  Pagination? _pagination;
  bool _isLoading = false;
  String? _error;
  String _selectedMonth = Formatters.currentMonth();

  List<Budget> get budgets => _budgets;
  Pagination? get pagination => _pagination;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedMonth => _selectedMonth;

  String _shiftMonth(String month, int delta) {
    final parts = month.split('-');
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final shifted = DateTime(date.year, date.month + delta);
    return '${shifted.year}-${shifted.month.toString().padLeft(2, '0')}';
  }

  void previousMonth() {
    _selectedMonth = _shiftMonth(_selectedMonth, -1);
    loadBudgets(force: true);
  }

  void nextMonth() {
    _selectedMonth = _shiftMonth(_selectedMonth, 1);
    loadBudgets(force: true);
  }

  void currentMonth() {
    _selectedMonth = Formatters.currentMonth();
    loadBudgets(force: true);
  }

  /// Load budgets for the selected month.
  Future<void> loadBudgets({bool force = false}) async {
    if (!force && _budgets.isNotEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _budgetService.list(month: _selectedMonth);
      _budgets = result.budgets;
      _pagination = result.pagination;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Create a new budget and refresh the list.
  Future<void> createBudget({
    required double amount,
    required String month,
    int? categoryId,
  }) async {
    await _budgetService.create(
      amount: amount,
      month: month,
      categoryId: categoryId,
    );
    await loadBudgets(force: true);
  }

  /// Update an existing budget and refresh the list.
  Future<void> updateBudget(
    int id, {
    required double amount,
    required String month,
    int? categoryId,
  }) async {
    await _budgetService.update(
      id,
      amount: amount,
      month: month,
      categoryId: categoryId,
    );
    await loadBudgets(force: true);
  }

  /// Delete a budget and refresh the list.
  Future<void> deleteBudget(int id) async {
    await _budgetService.delete(id);
    _budgets.removeWhere((b) => b.id == id);
    notifyListeners();
  }

  /// Clear all cached state — called on login/register/logout.
  void reset() {
    _budgets = [];
    _pagination = null;
    _isLoading = false;
    _error = null;
    _selectedMonth = Formatters.currentMonth();
    notifyListeners();
  }
}
