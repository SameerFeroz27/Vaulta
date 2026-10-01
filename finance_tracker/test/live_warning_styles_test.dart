import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/models/loan.dart';
import 'package:finance_tracker/utils/formatters.dart';
import 'package:finance_tracker/widgets/loans/loan_card.dart';
import 'package:finance_tracker/widgets/loans/record_payment_sheet.dart';

/// Live warnings — the inline notices that appear in response to app state — are set in
/// bold so they cannot be skimmed past. These lock that in for the two that render from
/// a plain model with no provider setup.
void main() {
  Loan loan({double paid = 0, double outstanding = 5000, double surplus = 0}) => Loan(
    id: 1,
    counterparty: 'Ali Raza',
    direction: LoanDirection.lent,
    principal: 5000,
    issueDate: '2026-09-01',
    paid: paid,
    outstanding: outstanding,
    surplus: surplus,
    state: outstanding > 0 ? LoanState.open : LoanState.settled,
  );

  testWidgets('the overpayment notice is bold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RecordPaymentSheet(loan: loan()))),
    );

    // The field pre-fills with the outstanding balance, so going over it raises the notice.
    await tester.enterText(find.byType(TextFormField).first, '7000');
    await tester.pumpAndSettle();

    final notice = tester.widget<Text>(find.textContaining('more than is owed'));
    expect(notice.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('an overpaid loan row headlines the surplus, never ₨0.00', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoanCard(
            loan: loan(paid: 6000, outstanding: 0, surplus: 1000),
            onTap: () {},
          ),
        ),
      ),
    );

    // The surplus is the headline figure, which is where the emphasis belongs.
    final headline = tester.widget<Text>(find.text(Formatters.currency(1000)));
    expect(headline.style?.fontWeight, FontWeight.bold);
    expect(find.text('over the amount'), findsOneWidget);

    // Nothing on the row can be read as still outstanding.
    expect(find.text(Formatters.currency(0)), findsNothing);
    expect(find.textContaining('outstanding'), findsNothing);
  });
}
