import '../models/transaction.dart';
import 'api_client.dart';

/// Handles transaction API calls.
class TransactionService {
  final ApiClient apiClient;

  TransactionService({required this.apiClient});

  /// List transactions with optional filters and pagination.
  Future<({List<Transaction> transactions, Pagination pagination})> list({
    int page = 1,
    int limit = 20,
    required TransactionFilters filters,
  }) async {
    final query = filters.toQueryMap()
      ..['page'] = page
      ..['limit'] = limit;

    final data = await apiClient.get('/transactions', query: query);
    final transactions = (data['transactions'] as List<dynamic>)
        .map((t) => Transaction.fromJson(t as Map<String, dynamic>))
        .toList();
    final pagination = Pagination.fromJson(
      data['pagination'] as Map<String, dynamic>,
    );

    return (transactions: transactions, pagination: pagination);
  }

  Future<Transaction> getById(int id) async {
    final data = await apiClient.get('/transactions/$id');
    return Transaction.fromJson(data['transaction']);
  }

  Future<Transaction> create(Map<String, dynamic> body) async {
    final data = await apiClient.post('/transactions', body: body);
    return Transaction.fromJson(data['transaction']);
  }

  Future<Transaction> update(int id, Map<String, dynamic> body) async {
    final data = await apiClient.put('/transactions/$id', body: body);
    return Transaction.fromJson(data['transaction']);
  }

  Future<void> delete(int id) async {
    await apiClient.delete('/transactions/$id');
  }

  Future<Transaction> confirm(int id) async {
    final data = await apiClient.post('/transactions/$id/confirm');
    return Transaction.fromJson(data['transaction']);
  }
}
