/// A monthly budget — either an overall budget (categoryId is null) or
/// a category-specific budget. Spending is computed live by the backend.
class Budget {
  final int id;
  final double amount;
  final int? categoryId; // null = overall monthly budget
  final String month; // YYYY-MM
  final String period; // always "monthly"
  final String? createdAt;
  final String? updatedAt;
  // Category info (only present for category-specific budgets)
  final String? categoryName;
  final String? categoryIcon;
  final String? categoryColor;
  // Computed spending fields
  final double spent;
  final double remaining;
  final double percentage;
  final bool overBudget;

  Budget({
    required this.id,
    required this.amount,
    this.categoryId,
    required this.month,
    required this.period,
    this.createdAt,
    this.updatedAt,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    required this.spent,
    required this.remaining,
    required this.percentage,
    required this.overBudget,
  });

  factory Budget.fromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'] as int,
      amount: double.parse(json['amount'].toString()),
      categoryId: json['categoryId'] as int?,
      month: json['month'] as String,
      period: json['period'] as String? ?? 'monthly',
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
      categoryName: json['categoryName'] as String?,
      categoryIcon: json['categoryIcon'] as String?,
      categoryColor: json['categoryColor'] as String?,
      spent: double.parse(json['spent'].toString()),
      remaining: double.parse(json['remaining'].toString()),
      percentage: double.parse(json['percentage'].toString()),
      overBudget: json['overBudget'] as bool? ?? false,
    );
  }

  /// Whether this is an overall monthly budget (not tied to a category).
  bool get isOverall => categoryId == null;
}
