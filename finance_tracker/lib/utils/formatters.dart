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

  /// Heading for a group of one day's transactions.
  ///
  /// "Today" and "Yesterday" are relative claims, so they are returned only when the date
  /// really is that day — compared as calendar days rather than elapsed hours, so a row at
  /// 23:00 yesterday is still yesterday. Any other date, a future one included, is named
  /// outright as the weekday and date, e.g. "Sun, Oct 11".
  static String dayLabel(String dateString) {
    final date = DateTime.parse(dateString);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);

    switch (today.difference(day).inDays) {
      case 0:
        return 'Today';
      case 1:
        return 'Yesterday';
      default:
        return DateFormat('EEE, MMM d').format(date);
    }
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

  /// Format a [DateTime] as a YYYY-MM-DD string, e.g. "2026-09-10".
  static String toDateString(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Shift a YYYY-MM month string by [delta] months,
  /// e.g. shiftMonth("2026-01", -1) → "2025-12".
  static String shiftMonth(String month, int delta) {
    final parts = month.split('-');
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final shifted = DateTime(date.year, date.month + delta);
    return '${shifted.year}-${shifted.month.toString().padLeft(2, '0')}';
  }
}
