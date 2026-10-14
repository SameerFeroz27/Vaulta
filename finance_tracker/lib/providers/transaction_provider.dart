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
  int _pendingReviewCount = 0;
  String? _error;

  List<Transaction> get transactions => _transactions;
  Pagination? get pagination => _pagination;
  TransactionFilters get filters => _filters;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _pagination?.hasNext ?? false;

  /// How many transactions are waiting on a direction decision. Kept live so the
  /// review queue stays discoverable instead of silently accumulating.
  int get pendingReviewCount => _pendingReviewCount;

  /// Load the first page of transactions with current filters.
  Future<void> loadTransactions() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Run the count alongside the list rather than after it.
      final countFuture = _fetchPendingReviewCount();
      final result = await _transactionService.list(page: 1, filters: _filters);
      _transactions = result.transactions;
      _pagination = result.pagination;
      _pendingReviewCount = await countFuture;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Failures here must not break the list itself, so they resolve to zero.
  Future<int> _fetchPendingReviewCount() async {
    try {
      return await _transactionService.countByStatus('needs_review');
    } catch (_) {
      return 0;
    }
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

  /// Change only the search term, keeping every other filter.
  ///
  /// Built explicitly rather than with copyWith, which treats null as "keep the old value"
  /// and so could never clear the term once set.
  Future<void> setSearch(String? search) async {
    final f = _filters;
    await setFilters(
      TransactionFilters(
        month: f.month,
        source: f.source,
        category: f.category,
        type: f.type,
        status: f.status,
        search: (search == null || search.trim().isEmpty)
            ? null
            : search.trim(),
        sort: f.sort,
        order: f.order,
      ),
    );
  }

  /// Fetch the rows waiting on a direction decision, for the review sheet.
  ///
  /// A failure here resolves to an empty list rather than touching [error]: the sheet still
  /// shows the count and can be dismissed, and the list underneath must not break.
  Future<List<Transaction>> fetchPendingReview() async {
    try {
      final result = await _transactionService.list(
        page: 1,
        limit: 50,
        filters: TransactionFilters(status: 'needs_review'),
      );
      return result.transactions;
    } catch (_) {
      return [];
    }
  }

  /// Confirm every transaction waiting on a direction decision, keeping the direction each
  /// already carries. Returns how many were confirmed, so the sheet can report it.
  Future<int> markAllAsReviewed() async {
    final pending = await fetchPendingReview();
    var confirmed = 0;
    for (final transaction in pending) {
      try {
        await _transactionService.confirm(transaction.id);
        confirmed++;
      } catch (_) {
        // One failure must not abandon the rest.
      }
    }

    if (confirmed > 0) {
      await loadTransactions();
      _refreshDependents();
    }
    return confirmed;
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

  /// Confirm a needs_review transaction, keeping the direction it already has.
  Future<bool> confirmTransaction(int id) async {
    try {
      await _transactionService.confirm(id);
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
      // The list is filtered locally here, so refresh the count explicitly in case
      // the deleted row was one of the pending ones.
      _pendingReviewCount = await _fetchPendingReviewCount();
      notifyListeners();
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
    _pendingReviewCount = 0;
    _error = null;
    notifyListeners();
  }
}
