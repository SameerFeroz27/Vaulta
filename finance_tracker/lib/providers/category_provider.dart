import 'package:flutter/foundation.dart' hide Category;

import '../models/category.dart';
import '../services/api_client.dart';
import '../services/category_service.dart';

/// Caches the category list for use in dropdowns and filters.
class CategoryProvider extends ChangeNotifier {
  final CategoryService _categoryService;

  CategoryProvider({required ApiClient apiClient})
    : _categoryService = CategoryService(apiClient: apiClient);

  List<Category> _categories = [];
  bool _isLoading = false;
  String? _error;

  List<Category> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Returns categories filtered by transaction type (for dropdowns).
  List<Category> forType(String type) {
    return _categories.where((c) => c.appliesTo(type)).toList();
  }

  /// Load categories if not already loaded. Pass [force] to always refresh.
  Future<void> loadCategories({bool force = false}) async {
    if (!force && _categories.isNotEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _categories = await _categoryService.list();
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Find a category by ID.
  Category? findById(int? id) {
    if (id == null) return null;
    return _categories.where((c) => c.id == id).firstOrNull;
  }

  /// Create a new category and add it to the local cache.
  /// Throws on error — caller should catch and display a SnackBar.
  Future<void> createCategory({
    required String name,
    required String icon,
    required String color,
    required String transactionType,
  }) async {
    final category = await _categoryService.create(
      name: name,
      icon: icon,
      color: color,
      transactionType: transactionType,
    );
    _categories.add(category);
    _categories.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  /// Update an existing category in the local cache.
  /// Throws on error — caller should catch and display a SnackBar.
  Future<void> updateCategory({
    required int id,
    required String name,
    required String icon,
    required String color,
    required String transactionType,
  }) async {
    final category = await _categoryService.update(
      id: id,
      name: name,
      icon: icon,
      color: color,
      transactionType: transactionType,
    );
    final index = _categories.indexWhere((c) => c.id == id);
    if (index != -1) {
      _categories[index] = category;
    }
    _categories.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
  }

  /// Delete a category and remove it from the local cache.
  /// Throws on error — caller should catch and display a SnackBar.
  Future<void> deleteCategory(int id) async {
    await _categoryService.delete(id);
    _categories.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  /// Clear all cached state — called on login/register/logout.
  void reset() {
    _categories = [];
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
