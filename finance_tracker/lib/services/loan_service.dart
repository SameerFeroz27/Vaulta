import '../models/loan.dart';
import '../models/transaction.dart' show Pagination;
import 'api_client.dart';

/// Handles loan API calls.
class LoanService {
  final ApiClient apiClient;

  LoanService({required this.apiClient});

  /// List active loans with optional filters and pagination.
  Future<({List<Loan> loans, Pagination pagination})> list({
    int page = 1,
    int limit = 20,
    required LoanFilters filters,
  }) async {
    final query = filters.toQueryMap()
      ..['page'] = page
      ..['limit'] = limit;

    final data = await apiClient.get('/loans', query: query);
    final loans = (data['loans'] as List<dynamic>)
        .map((l) => Loan.fromJson(l as Map<String, dynamic>))
        .toList();
    final pagination = Pagination.fromJson(
      data['pagination'] as Map<String, dynamic>,
    );

    return (loans: loans, pagination: pagination);
  }

  /// Per-person totals plus which people are overdue.
  /// Includes loans that have since been removed.
  Future<
      ({
        List<LoanSummaryPerson> people,
        int overdueCount,
        List<String> overduePeople,
      })> summary() async {
    final data = await apiClient.get('/loans/summary');
    final people = ((data['people'] ?? []) as List<dynamic>)
        .map((p) => LoanSummaryPerson.fromJson(p as Map<String, dynamic>))
        .toList();
    return (
      people: people,
      overdueCount: (data['overdueCount'] as int?) ?? 0,
      overduePeople: ((data['overduePeople'] ?? []) as List<dynamic>)
          .map((name) => name.toString())
          .toList(),
    );
  }

  /// A single loan with its repayment timeline.
  Future<({Loan loan, List<LoanPayment> payments})> getById(int id) async {
    final data = await apiClient.get('/loans/$id');
    final payments = ((data['payments'] ?? []) as List<dynamic>)
        .map((p) => LoanPayment.fromJson(p as Map<String, dynamic>))
        .toList();
    return (loan: Loan.fromJson(data['loan']), payments: payments);
  }

  Future<Loan> create(Map<String, dynamic> body) async {
    final data = await apiClient.post('/loans', body: body);
    return Loan.fromJson(data['loan']);
  }

  Future<Loan> update(int id, Map<String, dynamic> body) async {
    final data = await apiClient.put('/loans/$id', body: body);
    return Loan.fromJson(data['loan']);
  }

  /// Remove a loan. Returns how many of its own transactions were deleted —
  /// repayment history is kept, so those linger in the per-person summary.
  Future<int> delete(int id) async {
    final data = await apiClient.delete('/loans/$id');
    return (data['deletedTransactionCount'] as int?) ?? 0;
  }

  /// Record a repayment. Overpaying is allowed — the loan settles and the excess
  /// comes back as [surplusAdded] to be presented as a gift, tip or refund.
  Future<
      ({
        LoanPayment payment,
        Loan loan,
        bool settled,
        double surplusAdded,
      })> addPayment(int loanId, Map<String, dynamic> body) async {
    final data = await apiClient.post('/loans/$loanId/payments', body: body);
    return (
      payment: LoanPayment.fromJson(data['payment']),
      loan: Loan.fromJson(data['loan']),
      settled: data['settled'] as bool? ?? false,
      surplusAdded: (data['surplusAdded'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Remove a repayment and the transaction it created.
  Future<({Loan loan, List<LoanPayment> payments})> deletePayment(
    int loanId,
    int paymentId,
  ) async {
    await apiClient.delete('/loans/$loanId/payments/$paymentId');
    // The delete response carries the recomputed loan; the timeline is re-fetched
    // so the reopen-after-delete case is always consistent with the server.
    return getById(loanId);
  }
}
