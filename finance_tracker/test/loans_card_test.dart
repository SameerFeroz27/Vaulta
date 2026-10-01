import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/widgets/dashboard/loans_card.dart';

/// The dashboard lending section: two balances, and an overdue line that appears only
/// when something is actually late.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    double theyOwe = 45000,
    double iOwe = 12000,
    List<String> overduePeople = const [],
    int overdueCount = 0,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoansCard(
            theyOwe: theyOwe,
            iOwe: iOwe,
            overduePeople: overduePeople,
            overdueCount: overdueCount,
            onTap: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows what is owed in each direction', (tester) async {
    await pump(tester);

    expect(find.textContaining('Owed to me:'), findsOneWidget);
    expect(find.textContaining('I owe:'), findsOneWidget);
    expect(find.textContaining('45,000.00'), findsOneWidget);
    expect(find.textContaining('12,000.00'), findsOneWidget);
  });

  testWidgets('shows no overdue bar when nothing is late', (tester) async {
    await pump(tester);

    expect(find.textContaining('Overdue'), findsNothing);
  });

  testWidgets('names the one person who is late', (tester) async {
    await pump(tester, overduePeople: ['Ali'], overdueCount: 1);

    expect(find.text('Overdue: Ali'), findsOneWidget);
  });

  testWidgets('collapses further overdue people into "+N more"', (tester) async {
    await pump(tester, overduePeople: ['Ali', 'Bilal', 'Sana'], overdueCount: 3);

    expect(find.text('Overdue: Ali, +2 more'), findsOneWidget);
  });
}
