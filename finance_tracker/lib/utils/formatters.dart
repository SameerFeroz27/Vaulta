import 'package:intl/intl.dart';

import '../config/constants.dart';

/// Formatting helpers for currency, dates, and months.
class Formatters {
  Formatters._();

  /// Format a monetary amount with currency symbol, e.g. "₨ 1,234.50".
  static String currency(double amount, {String code = 'PKR'}) {
    final format = NumberFormat('#,##0.00', 'en_US');
    final symbol = Constants.currencySymbol(code);
    return '$symbol ${format.format(amount)}';
  }

  /// Format a date string (YYYY-MM-DD or ISO) as "Sep 10, 2026".
  static String date(String dateString) {
    final date = DateTime.parse(dateString);
    return DateFormat('MMM d, yyyy').format(date);
  }

  /// Format a date string as a short label "Sep 10".
  static String shortDate(String dateString) {
    final date = DateTime.parse(dateString);
    return DateFormat('MMM d').format(date);
  }

  /// Format a YYYY-MM string as "September 2026".
  static String month(String monthString) {
    final parts = monthString.split('-');
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    return DateFormat('MMMM yyyy').format(date);
  }

  /// Get the current month as YYYY-MM.
  static String currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }
}
