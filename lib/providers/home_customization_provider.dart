import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/home_actions.dart';

class HomeCustomizationProvider extends ChangeNotifier {
  String _companyId = '';
  List<String> _selectedIds = List.from(HomeActionsRegistry.defaultActionIds);
  bool _loaded = false;

  List<String> get selectedIds => List.unmodifiable(_selectedIds);
  bool get isLoaded => _loaded;

  String _prefsKey(String companyId) => 'homeQuickActions_v1_$companyId';

  /// Call when the active company changes (e.g. after login or company switch).
  Future<void> setCompanyId(String companyId) async {
    if (companyId.isEmpty) return;
    if (companyId == _companyId && _loaded) return;

    _companyId = companyId;
    _loaded = false;
    _selectedIds = List.from(HomeActionsRegistry.defaultActionIds);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey(companyId));
    if (saved != null && saved.isNotEmpty) {
      final valid = saved
          .where((id) => HomeActionsRegistry.getById(id) != null)
          .toList();
      if (valid.isNotEmpty) {
        _selectedIds = valid.take(HomeActionsRegistry.maxActions).toList();
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveActions(List<String> ids) async {
    if (_companyId.isEmpty) return;
    _selectedIds = ids.take(HomeActionsRegistry.maxActions).toList();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey(_companyId), _selectedIds);
  }

  Future<void> resetToDefaults() async {
    if (_companyId.isEmpty) return;
    _selectedIds = List.from(HomeActionsRegistry.defaultActionIds);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey(_companyId));
  }

  void reset() {
    _companyId = '';
    _selectedIds = List.from(HomeActionsRegistry.defaultActionIds);
    _loaded = false;
    notifyListeners();
  }

  static bool satisfiesFeatureGates(
    HomeAction action, {
    required bool billingEnabled,
    required bool barcodeEnabled,
    required bool vendorsEnabled,
    required bool pricingEnabled,
  }) {
    for (final gate in action.featureGates) {
      switch (gate) {
        case HomeActionFeatureGate.billing:
          if (!billingEnabled) return false;
        case HomeActionFeatureGate.barcode:
          if (!barcodeEnabled) return false;
        case HomeActionFeatureGate.vendors:
          if (!vendorsEnabled) return false;
        case HomeActionFeatureGate.pricing:
          if (!pricingEnabled) return false;
      }
    }
    return true;
  }

  /// First gate on the action that is not satisfied, or null if all satisfied.
  static HomeActionFeatureGate? firstUnsatisfiedFeatureGate(
    HomeAction action, {
    required bool billingEnabled,
    required bool barcodeEnabled,
    required bool vendorsEnabled,
    required bool pricingEnabled,
  }) {
    for (final gate in action.featureGates) {
      switch (gate) {
        case HomeActionFeatureGate.billing:
          if (!billingEnabled) return gate;
        case HomeActionFeatureGate.barcode:
          if (!barcodeEnabled) return gate;
        case HomeActionFeatureGate.vendors:
          if (!vendorsEnabled) return gate;
        case HomeActionFeatureGate.pricing:
          if (!pricingEnabled) return gate;
      }
    }
    return null;
  }

  List<HomeAction> getVisibleActions(
    Map<String, bool> permissions, {
    bool billingEnabled = false,
    bool barcodeEnabled = true,
    bool vendorsEnabled = true,
    bool pricingEnabled = true,
  }) {
    final List<HomeAction> result = [];
    for (final id in _selectedIds) {
      final action = HomeActionsRegistry.getById(id);
      if (action == null) continue;
      if (action.permissionKey != null &&
          permissions[action.permissionKey] != true) {
        continue;
      }
      if (!satisfiesFeatureGates(
        action,
        billingEnabled: billingEnabled,
        barcodeEnabled: barcodeEnabled,
        vendorsEnabled: vendorsEnabled,
        pricingEnabled: pricingEnabled,
      )) {
        continue;
      }
      result.add(action);
    }
    return result;
  }
}
