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

/// Vertical overhang of the raised centre "Quick Actions" button above the
/// pill's top edge.
const double kFloatingNavButtonOverhang = 40;

/// How much bottom inset a scrollable tab body should reserve so its content
/// can scroll fully into view above the floating pill.
///
/// Returns `0` on wide screens (>=560) where the [NavigationRail] is used
/// instead of the floating pill, so those layouts stay flush.
double floatingNavContentInset(BuildContext context) {
  if (Responsive.isWide(context)) return 0;
  return kFloatingNavBarHeight + kFloatingNavBarBottomGap + kFloatingNavExtraGap;
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
