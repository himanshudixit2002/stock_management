import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;

/// Collapses a burst of calls into a single deferred one.
///
/// Every search field in the app had its own `Timer? _debounce` plus the same
/// cancel-then-reschedule dance and a matching `dispose`, which was easy to get
/// half-right (a missed cancel leaks a pending callback into a disposed State).
///
/// ```dart
/// final _search = Debouncer();
/// ...
/// void _onSearchChanged(String v) => _search.run(() => setState(...));
/// @override
/// void dispose() { _search.dispose(); super.dispose(); }
/// ```
class Debouncer {
  /// Feels responsive while still skipping the intermediate keystrokes.
  static const Duration defaultDelay = Duration(milliseconds: 300);

  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = defaultDelay});

  /// True while a call is scheduled but has not fired yet — useful for showing
  /// a "searching…" affordance before the work actually starts.
  bool get isPending => _timer?.isActive ?? false;

  /// Schedules [action], replacing any call still waiting.
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Drops a pending call without running it.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Call from `State.dispose` so a pending callback never fires after unmount.
  void dispose() => cancel();
}
