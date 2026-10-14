import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/models/loan.dart';
import 'package:finance_tracker/utils/formatters.dart';
import 'package:finance_tracker/widgets/loans/loan_summary_table.dart';

/// The By person table: one row per person, with the net column that replaced Repaid.
void main() {
  LoanSummaryPerson person(
    String name, {
    double theyOwe = 0,
    double iOwe = 0,
    double repaid = 0,
    int loanCount = 1,
  }) {
    return LoanSummaryPerson(
      person: name,
      theyOwe: theyOwe,
      iOwe: iOwe,
      repaid: repaid,
      loanCount: loanCount,
      net: theyOwe - iOwe,
      state: theyOwe > 0 || iOwe > 0 ? LoanState.open : LoanState.settled,
    );
  }

  Future<void> pump(WidgetTester tester, List<LoanSummaryPerson> people) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LoanSummaryTable(people: people)),
      ),
    );
  }

  testWidgets('renders nothing at all without people', (tester) async {
    await pump(tester, []);

    expect(find.byType(Card), findsNothing);
  });

  testWidgets('marks a person whose loans were all removed', (tester) async {
    // Their last loan is gone, so nothing is owed and nothing is open — the row says
    // so rather than showing an unexplained blank.
    await pump(tester, [person('Ali Raza', repaid: 5000, loanCount: 0)]);

    expect(find.text('No active loans'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('shows what is owed each way and a net, never repaid', (tester) async {
    await pump(tester, [
      person('Ali Raza', theyOwe: 30000, repaid: 20000),
      person('Bilal Ahmed', iOwe: 50000),
    ]);

    expect(find.text('Ali Raza'), findsOneWidget);
    // One line per figure for each person, plus the totals block.
    expect(find.text('Owed to me'), findsNWidgets(3));
    expect(find.text('I owe'), findsNWidgets(3));
    expect(find.text('Net'), findsNWidgets(3));
    expect(find.text('Repaid'), findsNothing);
  });

  testWidgets('a large amount stays on its own line, with no overflow', (tester) async {
    // The reported problem: as a table column a figure this size was squeezed to a
    // different size than its neighbours. On its own line it has the full width.
    // (A layout overflow would throw here.)
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pump(tester, [person('Big Amounts', theyOwe: 9876543210.99)]);

    expect(find.text(Formatters.currency(9876543210.99)), findsOneWidget);
  });

  testWidgets('signs the net column by direction', (tester) async {
    await pump(tester, [person('Ali Raza', theyOwe: 30000, iOwe: 20000)]);

    // They owe me more than I owe them.
    expect(find.textContaining('+'), findsOneWidget);
  });

  testWidgets('shows totals only when there is more than one person', (tester) async {
    await pump(tester, [person('Ali Raza', theyOwe: 30000)]);
    expect(find.text('Total'), findsNothing);

    await pump(tester, [
      person('Ali Raza', theyOwe: 30000),
      person('Bilal Ahmed', iOwe: 50000),
    ]);
    expect(find.text('Total'), findsOneWidget);
    // The totals row carries the net sum as well.
    expect(find.textContaining('-'), findsWidgets);
  });

  testWidgets('renders a settled person with no outstanding as dashes', (tester) async {
    await pump(tester, [person('Sana Malik', repaid: 45000)]);

    // Both owed columns are zero.
    expect(find.text('—'), findsNWidgets(3));
  });
}
