/// Monthly expense/income trend for bar charts.
class ExpenseTrend {
  final int months;
  final List<TrendPoint> data;

  ExpenseTrend({required this.months, required this.data});

  factory ExpenseTrend.fromJson(Map<String, dynamic> json) {
    return ExpenseTrend(
      months: json['months'] as int,
      data: ((json['data'] ?? []) as List<dynamic>)
          .map((d) => TrendPoint.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TrendPoint {
  final String month;
  final double totalExpense;
  final double totalIncome;

  TrendPoint({
    required this.month,
    required this.totalExpense,
    required this.totalIncome,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) {
    return TrendPoint(
      month: json['month'] as String,
      totalExpense: (json['totalExpense'] as num).toDouble(),
      totalIncome: (json['totalIncome'] as num).toDouble(),
    );
  }
}
