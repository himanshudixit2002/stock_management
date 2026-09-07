/// The second line on each Settings hub row.
///
/// The hub trades a long flat list for nine category rows, which only works if
/// a row says what is currently configured behind it. "Dark · 6 quick actions"
/// answers the question most people open Settings to ask; "Appearance & home"
/// alone would force a tap to find out.
///
/// Every builder is a pure function of plain values — no `BuildContext`, no
/// provider — so the exact wording is pinned by unit tests instead of being
/// spot-checked by eye.
///
/// Each takes a `loaded` flag where its backing provider streams. Before the
/// company document arrives, `BillingSettingsProvider.settings` hands back
/// defaults, so a summary built eagerly would flash "$ · Tax 0% · INV-0001
/// next" and then correct itself. The static description is shown instead.
library;

import 'package:flutter/material.dart';

/// Joins the parts of a summary, dropping the empty ones.
String _join(List<String> parts) =>
    parts.where((p) => p.isNotEmpty).join(' · ');

/// `18` for a whole rate, `18.5` for a fractional one — never `18.00`.
String formatRate(double rate) => rate == rate.roundToDouble()
    ? rate.toStringAsFixed(0)
    : rate.toStringAsFixed(2);

/// `INV-0042`, matching how the number actually prints on an invoice.
String formatDocumentNumber(String prefix, int next) =>
    '$prefix-${next.toString().padLeft(4, '0')}';

String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'System theme',
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
};

String appearanceSummary({
  required ThemeMode mode,
  required int quickActionCount,
  required bool loaded,
}) {
  if (!loaded) return 'Theme and home quick actions';
  final actions = quickActionCount == 1
      ? '1 quick action'
      : '$quickActionCount quick actions';
  return _join([themeModeLabel(mode), actions]);
}

String notificationsSummary({
  required int enabled,
  required int total,
  required int expiryDays,
  required bool trayAvailable,
}) {
  // "this device" is not padding: notification preferences are stored per
  // device on purpose, so two people sharing a workspace do not overwrite each
  // other. Saying so on the row stops it reading as a workspace setting.
  final scope = trayAvailable ? 'this device' : 'in-app only';
  if (enabled == 0) return _join(['All alerts off', scope]);
  if (enabled >= total) return _join(['All $total alerts on', scope]);
  return _join(['$enabled of $total alerts', scope]);
}

String featuresSummary({
  required bool pricing,
  required bool vendors,
  required bool barcode,
  required bool billing,
  required bool loaded,
}) {
  if (!loaded) return 'Pricing, vendors, barcode and billing';
  const names = ['Pricing', 'Vendors', 'Barcode', 'Billing'];
  final states = [pricing, vendors, barcode, billing];

  final on = <String>[];
  final off = <String>[];
  for (var i = 0; i < names.length; i++) {
    (states[i] ? on : off).add(names[i]);
  }
  if (off.isEmpty) return 'All four features on';
  if (on.isEmpty) return 'All four features off';
  return '${on.join(', ')} on · ${off.join(', ')} off';
}

String billingSummary({
  required bool loaded,
  required String currencySymbol,
  required String taxLabel,
  required double taxRate,
  required bool enableTax,
  required String invoicePrefix,
  required int nextInvoiceNumber,
}) {
  if (!loaded) return 'Company profile, tax and numbering';
  final tax = enableTax
      ? '$taxLabel ${formatRate(taxRate)}%'
      : 'no tax';
  return _join([
    currencySymbol,
    tax,
    '${formatDocumentNumber(invoicePrefix, nextInvoiceNumber)} next',
  ]);
}

String catalogSummary({
  required int categories,
  required int companies,
  required int subCategories,
  required int locations,
  required bool loaded,
}) {
  if (!loaded) return 'Categories, companies, sub-categories and locations';
  String term(int n, String singular, String plural) =>
      n == 0 ? '' : '$n ${n == 1 ? singular : plural}';
  final parts = [
    term(categories, 'category', 'categories'),
    term(companies, 'company', 'companies'),
    term(subCategories, 'sub-category', 'sub-categories'),
    term(locations, 'location', 'locations'),
  ];
  final summary = _join(parts);
  return summary.isEmpty ? 'Nothing set up yet' : summary;
}

String teamSummary({
  required int roleCount,
  required bool rolesLoaded,
  required bool canManageUsers,
  required bool vendorsOn,
}) {
  if (!rolesLoaded) return 'Users, roles, vendors and customers';
  final roles = roleCount == 1 ? '1 role' : '$roleCount roles';
  return _join([
    roles,
    if (canManageUsers) 'users & overrides',
    if (vendorsOn) 'vendors',
  ]);
}

String dataSummary({
  required bool canImport,
  required bool canExport,
  required bool canDataHealth,
}) {
  final parts = [
    if (canImport) 'Import',
    if (canExport) 'Export',
    if (canDataHealth) 'Data health',
  ];
  return parts.isEmpty ? 'Bulk actions and workspace tools' : parts.join(', ');
}

String planSummary({
  required String planLabel,
  required bool usable,
  required String statusNote,
  required bool loaded,
}) {
  if (!loaded) return 'What your tier includes';
  final label = planLabel.isEmpty ? 'Current' : planLabel;
  if (usable) return '$label plan · active';
  final note = statusNote.trim();
  return note.isEmpty ? '$label plan' : '$label plan · $note';
}

String helpSummary({required String appVersion}) {
  final version = appVersion.trim();
  return version.isEmpty
      ? 'Guides, policies and app info'
      : 'Guides, legal and v$version';
}

String accountSummary({required String email, required String roleLabel}) {
  return _join([email, roleLabel]);
}
