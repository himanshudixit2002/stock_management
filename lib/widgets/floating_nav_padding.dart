import 'package:flutter/material.dart';
import '../utils/responsive.dart';

/// Shared geometry for the floating bottom navigation pill. Both
/// [FloatingBottomNav] and the tab bodies read these so the content and the
/// nav agree on how much space the pill occupies.

/// Inner height of the floating pill bar.
const double kFloatingNavBarHeight = 64;

/// Gap between the pill and the bottom safe area / gesture inset.
const double kFloatingNavBarBottomGap = 16;

/// Extra breathing room so the last scrollable item clears the pill.
const double kFloatingNavExtraGap = 32;

/// How much bottom inset a scrollable tab body should reserve so its content
/// can scroll fully into view above the floating pill.
///
/// Must mirror how [FloatingBottomNav] positions itself: it sits
/// `viewPadding.bottom + kFloatingNavBarBottomGap` up from the bottom edge and
/// is [kFloatingNavBarHeight] tall. Omitting the system gesture/navigation
/// inset here left the last 14-28px of every tab's content underneath the pill
/// on devices with a gesture bar or a 3-button navigation bar.
///
/// Returns `0` on wide screens (>=560) where the [NavigationRail] is used
/// instead of the floating pill, so those layouts stay flush — and `0` while
/// the software keyboard is up, because the pill hides then (see
/// [floatingNavHidden]). Reserving space for a pill that is not on screen
/// pushed the content of any tab with a text field — Settings search, the
/// product list's search — up by ~112px the moment the field took focus, and
/// dropped it again on blur.
double floatingNavContentInset(BuildContext context) {
  if (Responsive.isWide(context) || floatingNavHidden(context)) return 0;
  return MediaQuery.viewPaddingOf(context).bottom +
      kFloatingNavBarBottomGap +
      kFloatingNavBarHeight +
      kFloatingNavExtraGap;
}

/// The smallest bottom inset treated as "a keyboard is open".
///
/// Not `> 0`. On mobile web a bottom view inset can appear for reasons that
/// have nothing to do with a keyboard — browser chrome collapsing, or a
/// visual-viewport offset during a pinch — and on the phone layout the pill is
/// the *only* navigation there is, so hiding it on a stray inset would leave
/// someone unable to change tabs at all. Every software keyboard is far taller
/// than this.
const double kKeyboardInsetThreshold = 80;

/// True when the floating pill should not be drawn at all.
///
/// The shell's `Scaffold` resizes its body away from the keyboard, so a pill
/// positioned at `bottom: 0` is carried up and left hovering on top of the
/// keyboard while the user types. Hiding it is what every other app does, and
/// it is also why the content inset above collapses to zero.
bool floatingNavHidden(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom > kKeyboardInsetThreshold;

/// Distance from the bottom edge to the top of the floating pill — the lowest a
/// floating overlay (e.g. the Ask-AI button) may sit without covering it.
double floatingNavTopOffset(BuildContext context) {
  if (Responsive.isWide(context) || floatingNavHidden(context)) return 0;
  return MediaQuery.viewPaddingOf(context).bottom +
      kFloatingNavBarBottomGap +
      kFloatingNavBarHeight;
}

/// A trailing spacer to append to a tab body's scrollable content (e.g. the
/// last child of a `ListView`/`Column`) so the final items clear the floating
/// navigation pill. Collapses to nothing on wide screens.
///
/// For screens that build their own `padding`, prefer adding
/// [floatingNavContentInset] to the bottom value instead of nesting this.
class FloatingNavPadding extends StatelessWidget {
  const FloatingNavPadding({super.key});

  @override
  Widget build(BuildContext context) {
    final inset = floatingNavContentInset(context);
    if (inset == 0) return const SizedBox.shrink();
    return SizedBox(height: inset);
  }
}
