import '../models/category.dart';
import 'api_client.dart';

/// Handles category API calls.
class CategoryService {
  final ApiClient apiClient;

  CategoryService({required this.apiClient});

  /// Fetch all categories (global + user-specific).
  Future<List<Category>> list() async {
    final data = await apiClient.get('/categories');
    final categories = data['categories'] as List<dynamic>;
    return categories
        .map((json) => Category.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Create a new custom category for the authenticated user.
  Future<Category> create({
    required String name,
    required String icon,
    required String color,
    required String transactionType,
  }) async {
    final data = await apiClient.post('/categories', body: {
      'name': name,
      'icon': icon,
      'color': color,
      'transactionType': transactionType,
    });
    return Category.fromJson(data['category'] as Map<String, dynamic>);
  }

  /// Update an existing user-created category.
  Future<Category> update({
    required int id,
    required String name,
    required String icon,
    required String color,
    required String transactionType,
  }) async {
    final data = await apiClient.put('/categories/$id', body: {
      'name': name,
      'icon': icon,
      'color': color,
      'transactionType': transactionType,
    });
    return Category.fromJson(data['category'] as Map<String, dynamic>);
  }

  /// Delete a user-created category.
  Future<void> delete(int id) async {
    await apiClient.delete('/categories/$id');
  }
}
