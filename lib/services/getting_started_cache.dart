import 'package:shared_preferences/shared_preferences.dart';

/// Company-scoped local persistence for the Home "Getting Started" checklist.
///
/// Only the *dismissed* flag is persisted: every checklist step derives its
/// completion from real provider data (product count, stock transactions, team
/// size, billing toggle), so progress auto-updates and never needs a manual
/// checkmark store. Backed by `shared_preferences` (already a project
/// dependency — no new package, no Firestore schema) and keyed per company,
/// mirroring the Phase-1 [StatsCache] pattern.
class GettingStartedCache {
  GettingStartedCache._internal();
  static final GettingStartedCache _instance =
      GettingStartedCache._internal();
  factory GettingStartedCache() => _instance;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String _key(String companyId) => 'getting_started_dismissed_$companyId';

  /// Whether the user has dismissed the checklist for [companyId].
  Future<bool> isDismissed(String companyId) async {
    if (companyId.isEmpty) return false;
    final prefs = await _ensurePrefs();
    return prefs.getBool(_key(companyId)) ?? false;
  }

  /// Persists the dismissed state for [companyId].
  Future<void> setDismissed(String companyId, bool dismissed) async {
    if (companyId.isEmpty) return;
    final prefs = await _ensurePrefs();
    await prefs.setBool(_key(companyId), dismissed);
  }
}
