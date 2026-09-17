/// Monthly summary from GET /api/dashboard/summary.
class DashboardSummary {
  final String month;
  final double totalIncome;
  final double totalExpense;
  final double balance;
  final int transactionCount;
  final List<TopMerchant> topMerchants;

  DashboardSummary({
    required this.month,
    required this.totalIncome,
    required this.totalExpense,
    required this.balance,
    required this.transactionCount,
    required this.topMerchants,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      month: json['month'] as String,
      totalIncome: (json['totalIncome'] as num).toDouble(),
      totalExpense: (json['totalExpense'] as num).toDouble(),
      balance: (json['balance'] as num).toDouble(),
      transactionCount: json['transactionCount'] as int,
      topMerchants: ((json['topMerchants'] ?? []) as List<dynamic>)
          .map((m) => TopMerchant.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TopMerchant {
  final String merchant;
  final double totalSpent;

  TopMerchant({required this.merchant, required this.totalSpent});

  factory TopMerchant.fromJson(Map<String, dynamic> json) {
    return TopMerchant(
      merchant: json['merchant'] as String? ?? 'Unknown',
      totalSpent: (json['totalSpent'] as num).toDouble(),
    );
  }
}
