import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_tracker/widgets/motion/full_motion_route.dart';
import 'package:finance_tracker/widgets/motion/open_tile.dart';

/// Full motion is asked for unconditionally.
///
/// Flutter shortens every default-behaviour [AnimationController] to 5% of its duration
/// while `AccessibilityFeatures.disableAnimations` is set — one frame, which is what makes a
/// transition read as an instant cut. These tests pin the opt-out
/// (`AnimationBehavior.preserve`) and the route and tile that rely on it.
void main() {
  tearDown(() => debugSemanticsDisableAnimations = null);

  testWidgets('a preserved controller keeps its duration when animations are disabled', (
    tester,
  ) async {
    debugSemanticsDisableAnimations = true;

    await tester.pumpWidget(const MaterialApp(home: _ControllerHost()));
    final state = tester.state<_ControllerHostState>(
      find.byType(_ControllerHost),
    );

    state.plain.forward();
    state.preserved.forward();

    // 30 ms in: the plain controller's 400 ms was cut to 20 ms and has finished, while the
    // preserved one is still near the start of its full span.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(state.plain.value, 1.0);
    expect(state.preserved.value, lessThan(0.5));
  });

  testWidgets('a full-motion page route is still transitioning when a plain one is done', (
    tester,
  ) async {
    debugSemanticsDisableAnimations = true;

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('home')),
      ),
    );

    // The control: a default route collapses to its 5% duration and is finished almost
    // immediately.
    final plain = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('plain')),
    );
    navigator.currentState!.push(plain);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(plain.animation!.value, 1.0);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    // The full-motion route is still travelling at that point.
    final full = FullMotionPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('full')),
    );
    navigator.currentState!.push(full);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(full.animation!.value, greaterThan(0.0));
    expect(full.animation!.value, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(find.text('full'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the container transform opens a detail and collapses it again', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OpenTile(
              tileBuilder: (context, open) => InkWell(
                onTap: open,
                child: const SizedBox(
                  width: 120,
                  height: 60,
                  child: Center(child: Text('tile')),
                ),
              ),
              detailBuilder: (_) =>
                  const Scaffold(body: Center(child: Text('detail'))),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('tile'));
    await tester.pumpAndSettle();

    expect(find.text('detail'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Back collapses it: the detail is gone and the tile is untouched.
    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('detail'), findsNothing);
    expect(find.text('tile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a full-motion sheet still animates while animations are disabled', (
    tester,
  ) async {
    debugSemanticsDisableAnimations = true;

    late AnimationController sheetController;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                // Mirrors what showAppSheet does: the caller owns a preserved controller.
                sheetController = fullMotionController(
                  Navigator.of(context),
                  duration: const Duration(milliseconds: 300),
                  reverseDuration: const Duration(milliseconds: 220),
                  debugLabel: 'test sheet',
                );
                showModalBottomSheet<void>(
                  context: context,
                  transitionAnimationController: sheetController,
                  builder: (_) => const SizedBox(height: 100, child: Text('sheet')),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(sheetController.value, greaterThan(0.0));
    expect(sheetController.value, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ControllerHost extends StatefulWidget {
  const _ControllerHost();

  @override
  State<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends State<_ControllerHost>
    with TickerProviderStateMixin {
  late final AnimationController plain = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  late final AnimationController preserved = fullMotionController(
    this,
    duration: const Duration(milliseconds: 400),
    reverseDuration: const Duration(milliseconds: 400),
    debugLabel: 'preserved',
  );

  @override
  void dispose() {
    plain.dispose();
    preserved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
