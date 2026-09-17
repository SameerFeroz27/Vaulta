import '../models/budget.dart';
import '../models/transaction.dart' show Pagination;
import 'api_client.dart';

/// Handles budget API calls.
class BudgetService {
  final ApiClient apiClient;

  BudgetService({required this.apiClient});

  /// List budgets, optionally filtered by month.
  Future<({List<Budget> budgets, Pagination pagination})> list({
    String? month,
    int page = 1,
    int limit = 20,
  }) async {
    final query = <String, dynamic>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (month != null) query['month'] = month;

    final data = await apiClient.get('/budgets', query: query);
    final budgets = (data['budgets'] as List<dynamic>)
        .map((json) => Budget.fromJson(json as Map<String, dynamic>))
        .toList();

    final paginationJson = data['pagination'] as Map<String, dynamic>;
    final pPage = paginationJson['page'] as int;
    final pTotalPages = paginationJson['totalPages'] as int;
    final pagination = Pagination(
      page: pPage,
      limit: paginationJson['limit'] as int,
      total: paginationJson['total'] as int,
      totalPages: pTotalPages,
      hasNext: pPage < pTotalPages,
      hasPrev: pPage > 1,
    );

    return (budgets: budgets, pagination: pagination);
  }

  /// Create a new budget. Omit [categoryId] for an overall monthly budget.
  Future<Budget> create({
    required double amount,
    required String month,
    int? categoryId,
  }) async {
    final body = <String, dynamic>{'amount': amount, 'month': month};
    if (categoryId != null) body['categoryId'] = categoryId;

    final data = await apiClient.post('/budgets', body: body);
    return Budget.fromJson(data['budget'] as Map<String, dynamic>);
  }

  /// Update an existing budget.
  Future<Budget> update(
    int id, {
    required double amount,
    required String month,
    int? categoryId,
  }) async {
    final data = await apiClient.put(
      '/budgets/$id',
      body: {'amount': amount, 'month': month, 'categoryId': categoryId},
    );
    return Budget.fromJson(data['budget'] as Map<String, dynamic>);
  }

  /// Delete a budget.
  Future<void> delete(int id) async {
    await apiClient.delete('/budgets/$id');
  }
}
