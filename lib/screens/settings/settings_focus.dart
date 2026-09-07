import 'package:flutter/material.dart';

import '../../config/motion.dart';

/// How long a row arrived at from search stays highlighted.
const Duration kSettingsFlashDuration = Duration(milliseconds: 1600);

/// Scroll-to-and-flash for a settings page reached from search.
///
/// A search hit names a setting that lives inside a page — "GST" is a field
/// halfway down Billing Settings. Dropping the user at the top of that page and
/// letting them hunt for it undoes most of the value of having found it, so the
/// page scrolls the group into view and tints it briefly.
///
/// Anchors are per *group*, not per field: a page has five or six, they match
/// the breadcrumb the search result showed, and adding a field never requires a
/// new one.
mixin SettingsFocusMixin<T extends StatefulWidget> on State<T> {
  final Map<String, GlobalKey> _anchorKeys = {};
  String? _flashing;

  /// The key to attach to the group named [anchor], via `KeyedSubtree`.
  GlobalKey keyFor(String anchor) =>
      _anchorKeys.putIfAbsent(anchor, GlobalKey.new);

  /// Whether [anchor] is currently highlighted.
  bool isFlashing(String anchor) => _flashing == anchor;

  /// Scrolls [anchor] into view once the first frame has laid out, then
  /// flashes it. A null or unknown anchor is a no-op, so a stale deep link
  /// simply opens the page normally rather than failing.
  void focusAfterLayout(String? anchor) {
    if (anchor == null || anchor.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final target = _anchorKeys[anchor]?.currentContext;
      if (target == null) return;
      final reduce = reduceMotion(context);
      await Scrollable.ensureVisible(
        target,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        // Just below the top edge, so the group header is not flush against
        // the app bar.
        alignment: 0.12,
      );
      if (!mounted) return;
      setState(() => _flashing = anchor);
      await Future<void>.delayed(kSettingsFlashDuration);
      if (!mounted) return;
      setState(() => _flashing = null);
    });
  }
}

/// Reads the `String` anchor a settings route was pushed with.
///
/// Route arguments across the app are cast positionally, and
/// [AppRoutes.settings] in particular is cast `as String?` — so anything that
/// is not a string is treated as "no anchor" rather than crashing the route.
String? settingsAnchorOf(BuildContext context) {
  final args = ModalRoute.of(context)?.settings.arguments;
  return args is String ? args : null;
}
