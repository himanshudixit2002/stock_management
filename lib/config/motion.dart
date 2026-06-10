import 'package:flutter/material.dart';

// --- Press / tap feedback ---
const Duration kPressDuration = Duration(milliseconds: 140);
const Curve kPressCurve = Curves.easeInOut;

// --- Page transitions ---
const Duration kSlideTransitionDuration = Duration(milliseconds: 280);
const Curve kSlideTransitionCurve = Curves.easeOutCubic;

// --- Entrance / reveal (used by flutter_animate helpers) ---
const Duration kEntranceDuration = Duration(milliseconds: 420);
const Curve kEntranceCurve = Curves.easeOutCubic;

/// Delay between successive items in a staggered list/grid reveal.
const Duration kStaggerInterval = Duration(milliseconds: 55);

/// Cap so deep items in a long list don't wait too long before appearing.
const Duration kStaggerMaxDelay = Duration(milliseconds: 360);

/// Vertical offset (logical px) a widget slides up from as it fades in.
const double kEntranceSlideOffset = 14;

/// Duration for animated number count-ups (stat cards, totals).
const Duration kCountUpDuration = Duration(milliseconds: 900);

/// Whether the user/platform has requested reduced motion. When true, callers
/// should skip non-essential entrance/looping animations and render the final
/// state immediately (accessibility + lower-power devices).
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Staggered delay for the item at [index], capped by [kStaggerMaxDelay].
Duration staggerDelay(int index) {
  final d = kStaggerInterval * index;
  return d > kStaggerMaxDelay ? kStaggerMaxDelay : d;
}
