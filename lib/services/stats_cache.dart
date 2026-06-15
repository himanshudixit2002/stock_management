import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight, company-scoped local cache of last-known dashboard stats and
/// key settings toggles.
///
/// Purpose: let Home/Reports paint *real* numbers (product count, low-stock,
/// out-of-stock) and gate features correctly *before* Firestore returns, then
/// reconcile silently once fresh data lands. Backed by `shared_preferences`
/// (already a project dependency — no new package added).
///
/// This is a session/persisted seed only; it is never a source of truth. The
/// providers always overwrite it with authoritative Firestore data.
class StatsCache {
  StatsCache._internal();
  static final StatsCache _instance = StatsCache._internal();
  factory StatsCache() => _instance;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String _key(String companyId, String name) => 'stats_${companyId}_$name';

  // --- Product stats ---------------------------------------------------------

  /// Persists the latest authoritative product counters for [companyId].
  Future<void> saveProductStats(
    String companyId, {
    required int total,
    required int lowStock,
    required int outOfStock,
  }) async {
    if (companyId.isEmpty) return;
    final prefs = await _ensurePrefs();
    await prefs.setInt(_key(companyId, 'productTotal'), total);
    await prefs.setInt(_key(companyId, 'lowStock'), lowStock);
    await prefs.setInt(_key(companyId, 'outOfStock'), outOfStock);
  }

  /// Last-known product counters for [companyId], or null if never cached.
  Future<({int total, int lowStock, int outOfStock})?> readProductStats(
    String companyId,
  ) async {
    if (companyId.isEmpty) return null;
    final prefs = await _ensurePrefs();
    final total = prefs.getInt(_key(companyId, 'productTotal'));
    if (total == null) return null;
    return (
      total: total,
      lowStock: prefs.getInt(_key(companyId, 'lowStock')) ?? 0,
      outOfStock: prefs.getInt(_key(companyId, 'outOfStock')) ?? 0,
    );
  }

  // --- Settings toggles ------------------------------------------------------

  /// Persists the latest authoritative feature toggles for [companyId].
  Future<void> saveSettingsToggles(
    String companyId, {
    required bool pricingEnabled,
    required bool vendorsEnabled,
    required bool barcodeEnabled,
  }) async {
    if (companyId.isEmpty) return;
    final prefs = await _ensurePrefs();
    await prefs.setBool(_key(companyId, 'pricingEnabled'), pricingEnabled);
    await prefs.setBool(_key(companyId, 'vendorsEnabled'), vendorsEnabled);
    await prefs.setBool(_key(companyId, 'barcodeEnabled'), barcodeEnabled);
  }

  /// Last-known feature toggles for [companyId], or null if never cached.
  Future<({bool pricingEnabled, bool vendorsEnabled, bool barcodeEnabled})?>
  readSettingsToggles(String companyId) async {
    if (companyId.isEmpty) return null;
    final prefs = await _ensurePrefs();
    final pricing = prefs.getBool(_key(companyId, 'pricingEnabled'));
    if (pricing == null) return null;
    return (
      pricingEnabled: pricing,
      vendorsEnabled: prefs.getBool(_key(companyId, 'vendorsEnabled')) ?? true,
      barcodeEnabled: prefs.getBool(_key(companyId, 'barcodeEnabled')) ?? true,
    );
  }
}
