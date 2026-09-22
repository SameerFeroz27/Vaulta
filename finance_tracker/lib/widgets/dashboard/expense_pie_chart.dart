import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/expense_breakdown.dart';
import '../../utils/formatters.dart';

/// Pie chart with legend for expense breakdown by category or source.
class ExpensePieChart extends StatelessWidget {
  final String title;
  final ExpenseBreakdown breakdown;
  final List<Color>? defaultColors;
  final String currency;

  const ExpensePieChart({
    required this.title,
    required this.breakdown,
    this.defaultColors,
    this.currency = 'PKR',
    super.key,
  });

  Color _colorFor(int index, String? hex) {
    if (hex != null) {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    }
    const fallback = [
      Color(0xFF1976D2),
      Color(0xFF43A047),
      Color(0xFFFF9800),
      Color(0xFFE53935),
      Color(0xFF9C27B0),
      Color(0xFF00BCD4),
    ];
    final palette = defaultColors ?? fallback;
    return palette[index % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final items = breakdown.items.where((i) => i.total > 0).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No expenses this month',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: PieChart(
                      PieChartData(
                        sections: items.asMap().entries.map((entry) {
                          final i = entry.key;
                          final item = entry.value;
                          return PieChartSectionData(
                            value: item.total,
                            color: _colorFor(i, item.color),
                            title: '${item.percentage.toStringAsFixed(0)}%',
                            radius: 50,
                            titleStyle: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList(),
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: items.map((item) {
                        final index = items.indexOf(item);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _colorFor(index, item.color),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.icon != null
                                      ? '${item.icon} ${item.name}'
                                      : item.name,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                Formatters.currency(item.total,
                                    code: currency),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
