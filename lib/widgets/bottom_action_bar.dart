import 'package:flutter/material.dart';

/// Buttons pinned under a screen's content — a Scaffold's
/// [Scaffold.bottomNavigationBar] — centred and at most [maxWidth] wide.
///
/// That slot offers its child the full height of the screen. A plain [Center]
/// there takes all of it: the buttons float halfway down and the body is left
/// with no height at all, which is how Bulk Stock In, Bulk Edit and the role
/// editor came to show nothing but their buttons. This centres across and
/// stays exactly as tall as [child].
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.maxWidth,
    required this.child,
    this.minimum = EdgeInsets.zero,
  });

  final double maxWidth;
  final Widget child;

  /// Space kept clear around [child] even where the device has no inset.
  final EdgeInsets minimum;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: minimum,
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}
