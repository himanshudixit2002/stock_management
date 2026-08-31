import 'package:flutter/material.dart';

import '../config/theme.dart';

/// A "back to top" button that fades in once [controller] has scrolled past
/// [showAfter].
///
/// Every long list screen used to carry its own copy of this: a scroll
/// listener, a `bool _showScrollToTop`, and a `setState` on every threshold
/// crossing. Owning the state here also narrows the rebuild to the button
/// instead of the whole screen.
///
/// Renders nothing until [controller] is attached, so it is safe to place in a
/// `floatingActionButton` slot that builds before the list does.
class ScrollToTopButton extends StatefulWidget {
  final ScrollController controller;

  /// Scroll offset (logical px) past which the button appears.
  final double showAfter;

  /// Must be unique among the buttons on a single route.
  final String heroTag;

  const ScrollToTopButton({
    super.key,
    required this.controller,
    this.showAfter = 500,
    this.heroTag = 'scrollTop',
  });

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ScrollToTopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) return;
    final show = widget.controller.offset > widget.showAfter;
    if (show != _visible && mounted) setState(() => _visible = show);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: FloatingActionButton.small(
        heroTag: widget.heroTag,
        tooltip: 'Scroll to top',
        onPressed: _visible
            ? () => widget.controller.animateTo(
                0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
              )
            : null,
        backgroundColor: AppTheme.surface(context),
        foregroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.arrow_upward_rounded),
      ),
    );
  }
}
