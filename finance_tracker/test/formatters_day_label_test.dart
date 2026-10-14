import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:finance_tracker/utils/formatters.dart';

/// The heading over a group of one day's transactions.
///
/// "Today" and "Yesterday" are relative claims, so these lock down both halves of the rule:
/// when a relative label is allowed, and what a date that is neither of those is called
/// instead. Every date is built relative to now, so the suite does not go stale.
void main() {
  final now = DateTime.now();

  test('a row dated today reads Today', () {
    final today = DateTime(now.year, now.month, now.day);
    expect(Formatters.dayLabel(Formatters.toDateString(today)), 'Today');
  });

  test('a row dated yesterday reads Yesterday', () {
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    expect(Formatters.dayLabel(Formatters.toDateString(yesterday)), 'Yesterday');
  });

  test('late yesterday is still Yesterday, not Today', () {
    // Compared as calendar days, not elapsed hours: at 00:30 this is under two hours ago,
    // yet it is still yesterday's date.
    final lateYesterday = DateTime(now.year, now.month, now.day - 1, 23);
    expect(Formatters.dayLabel(lateYesterday.toIso8601String()), 'Yesterday');
  });

  test('an older date is named by weekday and date', () {
    final older = DateTime(now.year, now.month, now.day - 2);
    final expected = DateFormat('EEE, MMM d').format(older);

    expect(Formatters.dayLabel(Formatters.toDateString(older)), expected);
    expect(Formatters.dayLabel(Formatters.toDateString(older)), isNot('Yesterday'));
  });

  test('a future date is named, never called Today', () {
    // A dated-ahead row is possible on a device whose clock lags the server's, so it must
    // not be claimed as today.
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final label = Formatters.dayLabel(Formatters.toDateString(tomorrow));

    expect(label, isNot('Today'));
    expect(label, DateFormat('EEE, MMM d').format(tomorrow));
  });
}
