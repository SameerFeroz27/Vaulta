import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:finance_tracker/providers/auth_provider.dart';
import 'package:finance_tracker/screens/auth/login_screen.dart';
import 'package:finance_tracker/services/api_client.dart';

/// The sign-in screen's layout contract: it fits a standard phone without scrolling, and
/// every control keeps a touch target of at least 44 px.
void main() {
  Future<void> pumpLogin(WidgetTester tester) {
    return tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: AuthProvider(apiClient: ApiClient()),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
  }

  testWidgets('fits a standard phone height without scrolling', (tester) async {
    // A conservative "standard" phone: if it fits here it fits anything taller.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpLogin(tester);
    await tester.pumpAndSettle();

    final scrollable = find
        .descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;

    expect(
      position.maxScrollExtent,
      0,
      reason: 'the sign-in content must fit the viewport, so nothing scrolls',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every control keeps a 44 px touch target', (tester) async {
    await pumpLogin(tester);
    await tester.pumpAndSettle();

    double heightOf(Finder finder) => tester.getSize(finder).height;

    expect(heightOf(find.byType(Checkbox)), greaterThanOrEqualTo(44));
    expect(
      heightOf(find.widgetWithText(FilledButton, 'Sign in')),
      greaterThanOrEqualTo(44),
    );
    expect(
      heightOf(find.widgetWithText(TextButton, 'Forgot password?')),
      greaterThanOrEqualTo(44),
    );
    expect(
      heightOf(
        find.widgetWithText(TextButton, "Don't have an account? Create one"),
      ),
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('the checkbox drives the persistence choice', (tester) async {
    await pumpLogin(tester);
    await tester.pumpAndSettle();

    // Ticked by default, which preserves the current behaviour.
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    // The whole row is a target, not just the box.
    await tester.tap(find.text('Keep me signed in'));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });
}
