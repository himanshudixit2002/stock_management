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

// --- Playful Professional tokens ---
/// Duration for bottom-sheet content slide-up reveals.
const Duration kSheetDuration = Duration(milliseconds: 320);

/// Duration for hover lift / shimmer sweep interactions (web).
const Duration kHoverDuration = Duration(milliseconds: 200);

/// Duration of one cycle of a gentle live-indicator pulse.
const Duration kPulseDuration = Duration(milliseconds: 1200);

/// Spring-like overshoot curve for playful entrances and sheets.
const Curve kSpringCurve = Curves.easeOutBack;

/// Vertical lift (logical px) applied to cards/buttons on hover (web).
const double kHoverLiftOffset = 2.0;

/// Scale applied to cards/buttons while pressed.
const double kCardPressScale = 0.97;

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
