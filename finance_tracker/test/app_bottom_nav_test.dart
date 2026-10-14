import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/widgets/navigation/app_bottom_nav.dart';

/// The flat bar: one line that lands on the selected destination's slot, and labels that
/// stay inside their slot at the narrowest phone width.
void main() {
  const destinations = [
    AppNavDestination(icon: Icons.dashboard_outlined, label: 'Dashboard'),
    AppNavDestination(
      icon: Icons.receipt_long_outlined,
      label: 'Activity',
      badgeCount: 3,
    ),
    AppNavDestination(icon: Icons.handshake_outlined, label: 'Loans'),
    AppNavDestination(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  Future<void> pumpAt(
    WidgetTester tester,
    int index, {
    ValueChanged<int>? onTap,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            currentIndex: index,
            onTap: onTap ?? (_) {},
            destinations: destinations,
          ),
        ),
      ),
    );
  }

  testWidgets('the indicator lands on the selected slot and labels fit at 360 dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpAt(tester, 1);
    await tester.pumpAndSettle();

    final navRect = tester.getRect(find.byType(AppBottomNav));
    final slot = navRect.width / 4;

    var indicator = tester.getRect(find.byKey(const Key('nav-indicator')));
    expect(indicator.width, moreOrLessEquals(slot));
    expect(indicator.height, 3);
    expect(indicator.left - navRect.left, moreOrLessEquals(slot * 1));

    // Every label fits its slot at 360 dp, or it would clip or ellipsise.
    for (final label in ['Dashboard', 'Activity', 'Loans', 'Settings']) {
      expect(find.text(label), findsOneWidget);
      expect(
        tester.getSize(find.text(label)).width,
        lessThanOrEqualTo(slot),
        reason: '$label must fit its slot at 360 dp',
      );
    }

    // Move to the last destination: the line lands on that slot.
    await pumpAt(tester, 3);
    await tester.pumpAndSettle();
    indicator = tester.getRect(find.byKey(const Key('nav-indicator')));
    expect(indicator.left - navRect.left, moreOrLessEquals(slot * 3));
  });

  testWidgets('a tap reports the destination index', (tester) async {
    int? tapped;
    await pumpAt(tester, 0, onTap: (i) => tapped = i);

    await tester.tap(find.text('Loans'));

    expect(tapped, 2);
  });

  testWidgets('a count renders on its destination', (tester) async {
    await pumpAt(tester, 0);

    expect(find.text('3'), findsOneWidget);
  });
}
