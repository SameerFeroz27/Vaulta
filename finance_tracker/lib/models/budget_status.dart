/// Budget vs actual spending from GET /api/dashboard/budget-status.
class BudgetStatus {
  final String month;
  final BudgetOverall? overall;
  final List<BudgetCategoryStatus> categories;

  BudgetStatus({required this.month, this.overall, required this.categories});

  factory BudgetStatus.fromJson(Map<String, dynamic> json) {
    return BudgetStatus(
      month: json['month'] as String,
      overall: json['overall'] != null
          ? BudgetOverall.fromJson(json['overall'] as Map<String, dynamic>)
          : null,
      categories: ((json['categories'] ?? []) as List<dynamic>)
          .map((c) => BudgetCategoryStatus.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BudgetOverall {
  final double? budgetAmount;
  final double spent;
  final double? remaining;
  final double? percentage;
  final bool overBudget;

  BudgetOverall({
    this.budgetAmount,
    required this.spent,
    this.remaining,
    this.percentage,
    required this.overBudget,
  });

  factory BudgetOverall.fromJson(Map<String, dynamic> json) {
    return BudgetOverall(
      budgetAmount: (json['budgetAmount'] as num?)?.toDouble(),
      spent: (json['spent'] as num).toDouble(),
      remaining: (json['remaining'] as num?)?.toDouble(),
      percentage: (json['percentage'] as num?)?.toDouble(),
      overBudget: json['overBudget'] as bool? ?? false,
    );
  }
}

class BudgetCategoryStatus {
  final int budgetId;
  final double budgetAmount;
  final double spent;
  final double remaining;
  final double percentage;
  final bool overBudget;
  final int categoryId;
  final String categoryName;
  final String icon;
  final String color;

  BudgetCategoryStatus({
    required this.budgetId,
    required this.budgetAmount,
    required this.spent,
    required this.remaining,
    required this.percentage,
    required this.overBudget,
    required this.categoryId,
    required this.categoryName,
    required this.icon,
    required this.color,
  });

  factory BudgetCategoryStatus.fromJson(Map<String, dynamic> json) {
    return BudgetCategoryStatus(
      budgetId: json['budgetId'] as int,
      budgetAmount: (json['budgetAmount'] as num).toDouble(),
      spent: (json['spent'] as num).toDouble(),
      remaining: (json['remaining'] as num).toDouble(),
      percentage: (json['percentage'] as num).toDouble(),
      overBudget: json['overBudget'] as bool? ?? false,
      categoryId: json['categoryId'] as int,
      categoryName: json['categoryName'] as String? ?? 'Unknown',
      icon: json['icon'] as String? ?? '📁',
      color: json['color'] as String? ?? '#BDC3C7',
    );
  }
}
