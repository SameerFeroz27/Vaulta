import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/widgets/motion/stagger.dart';
import 'package:finance_tracker/widgets/motion/tab_slide.dart';

/// The two motion wrappers the tab shell relies on: an enter-only slide for a tab switch,
/// and a stagger that replays when the shell bumps the entry tick.
void main() {
  testWidgets('TabSlide enters the new child without error', (tester) async {
    await tester.pumpWidget(_host(0));
    await tester.pumpAndSettle();
    expect(find.text('zero'), findsOneWidget);

    // Changing the index drives didUpdateWidget, which reads the reduce-motion setting from
    // the element's context — that must be legal mid-update.
    await tester.pumpWidget(_host(1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('a stagger item replays when the entry tick changes', (tester) async {
    await tester.pumpWidget(_staggerHost(tick: 0));
    await tester.pumpAndSettle();
    expect(find.text('row'), findsOneWidget);

    // A fresh entry tick restarts the animation; the row must still be present and the
    // frame must not throw.
    await tester.pumpWidget(_staggerHost(tick: 1));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(find.text('row'), findsOneWidget);
  });
}

Widget _host(int index) => MaterialApp(
  home: Scaffold(
    body: TabSlide(
      index: index,
      child: Center(child: Text(index == 0 ? 'zero' : 'one')),
    ),
  ),
);

Widget _staggerHost({required int tick}) => MaterialApp(
  home: Scaffold(
    body: StaggerReplay(
      tick: tick,
      child: const StaggerItem(index: 2, child: Text('row')),
    ),
  ),
);
