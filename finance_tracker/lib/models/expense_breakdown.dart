/// Expense breakdown by category or source for pie charts.
class ExpenseBreakdown {
  final double totalExpense;
  final List<BreakdownItem> items;

  ExpenseBreakdown({required this.totalExpense, required this.items});

  factory ExpenseBreakdown.fromJson(Map<String, dynamic> json, String listKey) {
    return ExpenseBreakdown(
      totalExpense: (json['totalExpense'] as num).toDouble(),
      items: ((json[listKey] ?? []) as List<dynamic>)
          .map((e) => BreakdownItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A single slice in a pie chart — works for both categories and sources.
class BreakdownItem {
  final int? id;
  final String name;
  final String? icon;
  final String? color;
  final double total;
  final double percentage;

  BreakdownItem({
    this.id,
    required this.name,
    this.icon,
    this.color,
    required this.total,
    required this.percentage,
  });

  factory BreakdownItem.fromJson(Map<String, dynamic> json) {
    return BreakdownItem(
      id: json['categoryId'] as int? ?? json['sourceId'] as int?,
      name:
          json['categoryName'] as String? ??
          json['sourceName'] as String? ??
          'Unknown',
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      total: (json['total'] as num).toDouble(),
      percentage: (json['percentage'] as num).toDouble(),
    );
  }
}
