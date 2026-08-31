import 'package:intl/intl.dart';

/// Shared, cached [DateFormat] instances.
///
/// Constructing a `DateFormat` parses its pattern, and screens were building
/// the same handful of patterns inside every `build`. `'dd MMM yyyy'` alone was
/// re-declared in ten files, so the display format drifted whenever one of them
/// was edited in isolation.
class AppDates {
  const AppDates._();

  static final Map<String, DateFormat> _cache = {};

  /// A cached formatter for [pattern]. Use the named getters below for the
  /// common patterns; this is for genuine one-offs.
  static DateFormat of(String pattern) =>
      _cache[pattern] ??= DateFormat(pattern);

  /// `12 Mar 2025` — the app's default date display.
  static DateFormat get day => of('dd MMM yyyy');

  /// `12 Mar 2025, 04:30 PM` — date with time of day.
  static DateFormat get dayTime => of('dd MMM yyyy, hh:mm a');

  /// `12 Mar` — compact axis/label form.
  static DateFormat get shortDay => of('dd MMM');

  /// `2025-03-12` — a sortable grouping key, not for display.
  static DateFormat get isoDay => of('yyyy-MM-dd');
}
