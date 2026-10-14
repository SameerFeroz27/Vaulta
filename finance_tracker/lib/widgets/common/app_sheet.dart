import 'package:flutter/material.dart';

import '../../config/motion.dart';
import '../motion/full_motion_route.dart';

/// Opens a modal bottom sheet with the app's shared shell and motion.
///
/// The M3 reskin gives every sheet a 28 px top radius and a drag handle (from
/// `bottomSheetTheme`), and the motion spec asks for 300 ms in and 220 ms out. Routing
/// every call site through here is what stops the four of them drifting apart.
///
/// The sheet owns a controller we create so its slide can opt out of Flutter's
/// reduce-motion scaling, which would otherwise cut the animation to a single frame.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) async {
  // A Navigator is a TickerProvider, and the route leaves ownership of a supplied
  // controller with the caller.
  final controller = fullMotionController(
    Navigator.of(context),
    duration: Motion.sheetIn,
    reverseDuration: Motion.sheetOut,
    debugLabel: 'AppBottomSheet',
  );

  final result = await showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    useSafeArea: true,
    transitionAnimationController: controller,
    builder: builder,
  );

  // The future resolves as the route starts closing, so the controller is released only
  // once the closing animation has actually finished.
  if (controller.status == AnimationStatus.dismissed) {
    controller.dispose();
  } else {
    controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) controller.dispose();
    });
  }

  return result;
}
