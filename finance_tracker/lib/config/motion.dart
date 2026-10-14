import 'package:flutter/material.dart';

/// Every timing in the app's motion, in one place.
///
/// The values come from the tab & tile transitions guide, mirrored in
/// `docs/ARCHITECTURE.md` §10.2. Tuning a transition should be a one-line change here.
class Motion {
  Motion._();

  /// A tapped tile growing into its detail screen.
  static const Duration container = Duration(milliseconds: 320);

  /// Collapsing back. Slightly quicker than opening.
  static const Duration collapse = Duration(milliseconds: 300);

  /// Detail content fading in, and the delay before it starts. The header arrives at
  /// [contentDelay] and the rows and actions at [bodyDelay], so content never animates on
  /// the same beat as the container carrying it.
  static const Duration content = Duration(milliseconds: 150);
  static const Duration contentDelay = Duration(milliseconds: 110);
  static const Duration bodyDelay = Duration(milliseconds: 170);

  /// A tab switch sliding the incoming screen in.
  static const Duration tabSlide = Duration(milliseconds: 300);

  /// The nav indicator gliding between destinations. Same curve as the slide.
  static const Duration indicator = Duration(milliseconds: 280);

  /// Bottom sheets, in and out.
  static const Duration sheetIn = Duration(milliseconds: 300);
  static const Duration sheetOut = Duration(milliseconds: 220);
  static const Duration scrim = Duration(milliseconds: 220);

  /// List stagger on entry, and how many items take their turn before the rest just appear.
  static const Duration stagger = Duration(milliseconds: 40);
  static const int staggerMax = 6;

  /// Emphasized: a fast start and a soft landing. Standard is the milder pair.
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve standard = Cubic(0.4, 0, 0.2, 1);

  /// Delay for item [index] in a staggered list, capped at [staggerMax] so a long list does
  /// not keep the user waiting on items they cannot see yet.
  static Duration staggerFor(int index) => Duration(
    milliseconds: (index < staggerMax ? index : staggerMax - 1) *
        stagger.inMilliseconds,
  );
}
