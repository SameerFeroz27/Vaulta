import 'package:flutter/foundation.dart';

import '../models/transaction.dart';
import '../services/api_client.dart';
import '../services/transaction_service.dart';
import 'budget_provider.dart';
import 'dashboard_provider.dart';

/// Manages the transaction list: pagination, filters, and CRUD operations.
class TransactionProvider extends ChangeNotifier {
  final TransactionService _transactionService;
  DashboardProvider? _dashboardProvider;
  BudgetProvider? _budgetProvider;

  TransactionProvider({required ApiClient apiClient})
    : _transactionService = TransactionService(apiClient: apiClient);

  /// Wire dependent providers so the dashboard and budgets refresh
  /// automatically whenever a transaction is created, updated, or deleted.
  void setDependents(DashboardProvider? dashboard, BudgetProvider? budget) {
    _dashboardProvider = dashboard;
    _budgetProvider = budget;
  }

  void _refreshDependents() {
    _dashboardProvider?.loadDashboard();
    _budgetProvider?.loadBudgets(force: true);
  }

  List<Transaction> _transactions = [];
  Pagination? _pagination;
  TransactionFilters _filters = TransactionFilters();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;

  List<Transaction> get transactions => _transactions;
  Pagination? get pagination => _pagination;
  TransactionFilters get filters => _filters;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _pagination?.hasNext ?? false;

  /// Load the first page of transactions with current filters.
  Future<void> loadTransactions() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _transactionService.list(page: 1, filters: _filters);
      _transactions = result.transactions;
      _pagination = result.pagination;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load the next page (for infinite scroll).
  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final result = await _transactionService.list(
        page: (_pagination?.page ?? 1) + 1,
        filters: _filters,
      );
      _transactions = [..._transactions, ...result.transactions];
      _pagination = result.pagination;
    } catch (_) {}

    _isLoadingMore = false;
    notifyListeners();
  }

  /// Update filters and reload.
  Future<void> setFilters(TransactionFilters filters) async {
    _filters = filters;
    await loadTransactions();
  }

  /// Clear all filters and reload.
  Future<void> clearFilters() async {
    _filters = TransactionFilters();
    await loadTransactions();
  }

  /// Create a new transaction and refresh the list.
  Future<bool> createTransaction(Map<String, dynamic> body) async {
    try {
      await _transactionService.create(body);
      await loadTransactions();
      _refreshDependents();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update a transaction and refresh the list.
  Future<bool> updateTransaction(int id, Map<String, dynamic> body) async {
    try {
      await _transactionService.update(id, body);
      await loadTransactions();
      _refreshDependents();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Delete a transaction and refresh the list.
  Future<bool> deleteTransaction(int id) async {
    try {
      await _transactionService.delete(id);
      _transactions = _transactions.where((t) => t.id != id).toList();
      notifyListeners();
      _refreshDependents();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Clear all cached state — called on login/register/logout.
  void reset() {
    _transactions = [];
    _pagination = null;
    _filters = TransactionFilters();
    _isLoading = false;
    _isLoadingMore = false;
    _error = null;
    notifyListeners();
  }
}
