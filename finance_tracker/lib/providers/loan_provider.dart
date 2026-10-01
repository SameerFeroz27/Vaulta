import 'package:flutter/foundation.dart';

import '../models/loan.dart';
import '../models/transaction.dart' show Pagination;
import '../services/api_client.dart';
import '../services/loan_service.dart';
import 'transaction_provider.dart';

/// What the UI needs back after recording a repayment, so it can tell the user
/// when they overpaid.
class LoanPaymentResult {
  final Loan loan;
  final bool settled;
  final double surplusAdded;

  LoanPaymentResult({
    required this.loan,
    required this.settled,
    required this.surplusAdded,
  });
}

/// Manages loans: the per-person summary, the active list, and mutations.
class LoanProvider extends ChangeNotifier {
  final LoanService _loanService;
  TransactionProvider? _transactionProvider;

  LoanProvider({required ApiClient apiClient})
    : _loanService = LoanService(apiClient: apiClient);

  /// Loan money movements land in the ledger, so refresh it when a loan changes.
  void setDependents(TransactionProvider? transactions) {
    _transactionProvider = transactions;
  }

  void _refreshLedger() => _transactionProvider?.loadTransactions();

  List<Loan> _loans = [];
  List<LoanSummaryPerson> _summary = [];
  Pagination? _pagination;
  LoanFilters _filters = LoanFilters();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _overdueCount = 0;
  List<String> _overduePeople = [];
  String? _error;
  String? _errorCode;

  List<Loan> get loans => _loans;
  List<LoanSummaryPerson> get summary => _summary;
  Pagination? get pagination => _pagination;
  LoanFilters get filters => _filters;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _pagination?.hasNext ?? false;
  String? get error => _error;

  /// The backend error code behind [error], when there was one. Lets the UI treat a
  /// CONFLICT (a payment already recorded under this idempotency key) as "already done".
  String? get errorCode => _errorCode;

  /// Record a failure so both the message and the machine-readable code are available.
  void _recordError(Object e) {
    _error = e.toString();
    _errorCode = e is ApiException ? e.code : null;
  }

  /// Active loans past their due date, across every person (hidden loans excluded).
  int get overdueCount => _overdueCount;

  /// Who is overdue, one entry per person, for naming them on the dashboard.
  List<String> get overduePeople => _overduePeople;

  /// Totals across every person. Includes removed loans, so a person dropped from
  /// the active list still contributes the amount they repaid.
  double get totalTheyOwe => _sum((p) => p.theyOwe);
  double get totalIOwe => _sum((p) => p.iOwe);

  double _sum(double Function(LoanSummaryPerson) pick) =>
      _summary.fold(0.0, (total, person) => total + pick(person));

  /// Load the first page of loans alongside the per-person summary.
  Future<void> loadLoans() async {
    _isLoading = true;
    _error = null;
    _errorCode = null;
    notifyListeners();

    try {
      // Both feed the same screen, so run them together rather than in sequence.
      final summaryFuture = _loanService.summary();
      final result = await _loanService.list(page: 1, filters: _filters);
      _loans = result.loans;
      _pagination = result.pagination;

      final summary = await summaryFuture;
      _summary = summary.people;
      _overdueCount = summary.overdueCount;
      _overduePeople = summary.overduePeople;
    } catch (e) {
      _recordError(e);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refresh only the summary — cheaper than [loadLoans] for the dashboard card.
  /// Failures here must not break the card, so they leave the totals as they were.
  Future<void> loadSummary() async {
    try {
      final summary = await _loanService.summary();
      _summary = summary.people;
      _overdueCount = summary.overdueCount;
      _overduePeople = summary.overduePeople;
      notifyListeners();
    } catch (_) {}
  }

  /// Load the next page (for infinite scroll).
  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final result = await _loanService.list(
        page: (_pagination?.page ?? 1) + 1,
        filters: _filters,
      );
      _loans = [..._loans, ...result.loans];
      _pagination = result.pagination;
    } catch (_) {}

    _isLoadingMore = false;
    notifyListeners();
  }

  /// Update filters and reload.
  Future<void> setFilters(LoanFilters filters) async {
    _filters = filters;
    await loadLoans();
  }

  /// Clear all filters and reload.
  Future<void> clearFilters() async {
    _filters = LoanFilters();
    await loadLoans();
  }

  /// Fetch one loan with its repayment timeline. Returns null on failure, with
  /// the reason left on [error].
  Future<({Loan loan, List<LoanPayment> payments})?> getLoanDetail(int id) async {
    try {
      return await _loanService.getById(id);
    } catch (e) {
      _recordError(e);
      notifyListeners();
      return null;
    }
  }

  Future<bool> createLoan(Map<String, dynamic> body) async {
    try {
      await _loanService.create(body);
      await loadLoans();
      _refreshLedger();
      return true;
    } catch (e) {
      _recordError(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateLoan(int id, Map<String, dynamic> body) async {
    try {
      await _loanService.update(id, body);
      await loadLoans();
      _refreshLedger();
      return true;
    } catch (e) {
      _recordError(e);
      notifyListeners();
      return false;
    }
  }

  /// Remove a loan and the transactions it created. Repayment history is kept, so
  /// the summary is re-fetched rather than patched locally.
  Future<bool> deleteLoan(int id) async {
    try {
      await _loanService.delete(id);
      await loadLoans();
      _refreshLedger();
      return true;
    } catch (e) {
      _recordError(e);
      notifyListeners();
      return false;
    }
  }

  /// Record a repayment. Overpaying succeeds — the caller reports the surplus.
  Future<LoanPaymentResult?> addPayment(
    int loanId,
    Map<String, dynamic> body,
  ) async {
    _errorCode = null;
    try {
      final result = await _loanService.addPayment(loanId, body);
      await loadLoans();
      _refreshLedger();
      return LoanPaymentResult(
        loan: result.loan,
        settled: result.settled,
        surplusAdded: result.surplusAdded,
      );
    } catch (e) {
      _recordError(e);
      notifyListeners();
      return null;
    }
  }

  /// Remove a repayment. A settled loan reopens if this drops it below the principal.
  Future<bool> deletePayment(int loanId, int paymentId) async {
    try {
      await _loanService.deletePayment(loanId, paymentId);
      await loadLoans();
      _refreshLedger();
      return true;
    } catch (e) {
      _recordError(e);
      notifyListeners();
      return false;
    }
  }

  /// Clear all cached state — called on login/register/logout.
  void reset() {
    _loans = [];
    _summary = [];
    _pagination = null;
    _filters = LoanFilters();
    _isLoading = false;
    _isLoadingMore = false;
    _overdueCount = 0;
    _overduePeople = [];
    _error = null;
    _errorCode = null;
    notifyListeners();
  }
}
