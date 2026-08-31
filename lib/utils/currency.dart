import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../providers/billing_settings_provider.dart';

/// Single source of truth for money display.
///
/// The currency symbol is user-configurable (Settings → Billing → currency
/// symbol). Before this helper existed only the billing screens honoured it —
/// products, orders, POS, returns and reports read the hard-coded
/// [AppTheme.currencySymbol], so a company that switched to `$` still saw `₹`
/// nearly everywhere. Route every money string through here so the setting
/// applies app-wide and grouping/decimals stay consistent.
///
/// [NumberFormat] parses its pattern on construction, so formatters are cached
/// here instead of being rebuilt inside `build`.
class Money {
  const Money._();

  /// Used when billing settings have not loaded yet, or the symbol was cleared.
  /// Matches the historical hard-coded default.
  static const String fallbackSymbol = AppTheme.currencySymbol;

  static final Map<String, NumberFormat> _formatters = {};

  static NumberFormat _formatter(int decimals, String? locale) {
    final key = '$decimals|${locale ?? ''}';
    return _formatters[key] ??= NumberFormat(
      decimals > 0 ? '#,##0.${'0' * decimals}' : '#,##0',
      locale,
    );
  }

  /// Normalizes a raw configured symbol, falling back when unset.
  static String symbolOrFallback(String? symbol) {
    final trimmed = symbol?.trim() ?? '';
    return trimmed.isEmpty ? fallbackSymbol : trimmed;
  }

  /// The company's configured currency symbol.
  ///
  /// Defaults to watching so a currency change repaints. Pass `listen: false`
  /// from callbacks, `initState` and other non-build contexts.
  static String symbolOf(BuildContext context, {bool listen = true}) {
    final settings = listen
        ? context.watch<BillingSettingsProvider>().settings
        : context.read<BillingSettingsProvider>().settings;
    return symbolOrFallback(settings.currencySymbol);
  }

  /// Formatted amount with the company's symbol, e.g. `₹1,234.50`.
  static String of(
    BuildContext context,
    num value, {
    int decimals = 2,
    String? locale,
    bool listen = true,
  }) => withSymbol(
    symbolOf(context, listen: listen),
    value,
    decimals: decimals,
    locale: locale,
  );

  /// For callers that already resolved the symbol, or have no [BuildContext]
  /// (the PDF/Excel services).
  static String withSymbol(
    String symbol,
    num value, {
    int decimals = 2,
    String? locale,
  }) =>
      '${symbolOrFallback(symbol)}${_formatter(decimals, locale).format(value)}';

  /// Grouped number with no symbol — for rows that render the symbol separately
  /// (table headers, text-field prefixes).
  static String number(num value, {int decimals = 2, String? locale}) =>
      _formatter(decimals, locale).format(value);

  /// Abbreviated Indian-style magnitudes for charts and stat tiles:
  /// `₹1.2Cr`, `₹3.4L`, `₹5.6K`. Falls back to the full format below 1,000.
  static String compact(BuildContext context, num value, {bool listen = true}) =>
      compactWithSymbol(symbolOf(context, listen: listen), value);

  static String compactWithSymbol(String symbol, num value) {
    final sym = symbolOrFallback(symbol);
    final v = value.toDouble();
    final abs = v.abs();
    if (abs >= 1e7) return '$sym${(v / 1e7).toStringAsFixed(1)}Cr';
    if (abs >= 1e5) return '$sym${(v / 1e5).toStringAsFixed(1)}L';
    if (abs >= 1e3) return '$sym${(v / 1e3).toStringAsFixed(1)}K';
    return withSymbol(sym, v);
  }

  /// Abbreviated magnitude without a currency symbol (chart axis labels).
  static String compactNumber(num value) {
    final v = value.toDouble();
    final abs = v.abs();
    if (abs >= 1e7) return '${(v / 1e7).toStringAsFixed(1)}Cr';
    if (abs >= 1e5) return '${(v / 1e5).toStringAsFixed(1)}L';
    if (abs >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
    return number(v);
  }
}
