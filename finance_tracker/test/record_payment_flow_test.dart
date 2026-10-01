import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:finance_tracker/providers/loan_provider.dart';
import 'package:finance_tracker/screens/loans/loan_detail_screen.dart';
import 'package:finance_tracker/services/api_client.dart';
import 'package:finance_tracker/utils/formatters.dart';
import 'package:finance_tracker/widgets/loans/record_payment_sheet.dart';

/// The record-payment path end to end: opening the sheet from the loan detail screen,
/// the overpayment notice, and the exact payload posted.
///
/// It also pins the modal's provider access. A bottom sheet is a separate route, so it
/// can only read [LoanProvider] while the provider sits *above* MaterialApp — as it does
/// in main.dart. Nesting it inside MaterialApp breaks the sheet with
/// ProviderNotFoundException, which this arrangement catches.
void main() {
  http.Response ok(Map<String, dynamic> data) => http.Response(
    jsonEncode({'success': true, 'data': data}),
    200,
    headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> loanJson({
    double paid = 0,
    double outstanding = 5000,
    String state = 'open',
  }) => {
    'id': 1,
    'counterparty': 'Ali Raza',
    'direction': 'lent',
    'principal': 5000,
    'issueDate': '2026-09-01',
    'dueDate': null,
    'notes': null,
    'paid': paid,
    'outstanding': outstanding,
    'surplus': 0,
    'state': state,
    'overdue': false,
  };

  testWidgets('records a payment from the sheet end to end', (tester) async {
    String? paymentBody;

    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path.contains('/payments')) {
        paymentBody = request.body;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'payment': {
                'id': 7,
                'amount': 7000,
                'paymentDate': '2026-09-24',
                'transactionId': 99,
                'note': null,
              },
              'loan': loanJson(paid: 7000, outstanding: 0, state: 'settled'),
              'settled': true,
              'surplusAdded': 2000,
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.contains('/loans/1')) {
        return ok({'loan': loanJson(), 'payments': <dynamic>[]});
      }
      return ok({'people': <dynamic>[]});
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<LoanProvider>.value(
        value: LoanProvider(apiClient: ApiClient(httpClient: client)),
        child: const MaterialApp(home: LoanDetailScreen(loanId: 1)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordPaymentSheet), findsOneWidget);

    // Go over the outstanding balance so the overpayment notice shows too.
    await tester.enterText(
      find
          .descendant(
            of: find.byType(RecordPaymentSheet),
            matching: find.byType(TextFormField),
          )
          .first,
      '7000',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('more than is owed'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(RecordPaymentSheet),
        matching: find.widgetWithText(FilledButton, 'Record payment'),
      ),
    );
    await tester.pumpAndSettle();

    expect(paymentBody, isNotNull, reason: 'the sheet should have posted the payment');
    final posted = jsonDecode(paymentBody!) as Map<String, dynamic>;
    expect(posted['amount'], 7000.0);
    expect(posted['paymentDate'], Formatters.toDateString(DateTime.now()));
    expect(posted['recordTransaction'], isTrue);
    expect(posted['idempotencyKey'], startsWith('loan-payment-1-'));
    expect(find.byType(RecordPaymentSheet), findsNothing);
  });
}
