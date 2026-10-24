import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/feature_map.dart';
import '../config/feature_visibility.dart';
import '../config/home_actions.dart';

/// The blocks Home is built from, in display order.
enum HomeSection {
  quickActions,
  stats,
  gettingStarted,
  aiInsights,
  favoritesAndTips,
  featureShortcuts,
  recentActivity,
}

/// How a [HomeSection] is presented in Home customization.
class HomeSectionInfo {
  const HomeSectionInfo(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

class HomeCustomizationProvider extends ChangeNotifier {
  String _companyId = '';
  List<String> _selectedIds = List.from(HomeActionsRegistry.defaultActionIds);
  Set<HomeSection> _hiddenSections = Set.of(defaultHiddenSections);
  bool _loaded = false;

  /// Sections Home starts without. The AI panel makes several backend calls
  /// on every visit and fills most of a phone screen, so it is opt-in.
  static const Set<HomeSection> defaultHiddenSections = {
    HomeSection.aiInsights,
  };

  static const Map<HomeSection, HomeSectionInfo> sectionInfo = {
    HomeSection.quickActions: HomeSectionInfo(
      'Quick actions',
      'Your shortcut cards at the top',
      Icons.bolt_rounded,
    ),
    HomeSection.stats: HomeSectionInfo(
      'At a glance',
      'Stock levels and what needs attention',
      Icons.insights_rounded,
    ),
    HomeSection.gettingStarted: HomeSectionInfo(
      'Getting started',
      'Setup checklist for a new workspace (admins)',
      Icons.flag_rounded,
    ),
    HomeSection.aiInsights: HomeSectionInfo(
      'AI insights',
      'Anomalies, reorder ideas and demand projections',
      Icons.auto_awesome_rounded,
    ),
    HomeSection.favoritesAndTips: HomeSectionInfo(
      'Favorites and tips',
      'Pinned products and a daily tip, under "Show more"',
      Icons.favorite_rounded,
    ),
    HomeSection.featureShortcuts: HomeSectionInfo(
      'Feature shortcuts',
      'Orders, billing, inventory and report tiles',
      Icons.grid_view_rounded,
    ),
    HomeSection.recentActivity: HomeSectionInfo(
      'Recent activity',
      'The latest stock movements',
      Icons.history_rounded,
    ),
  };

  List<String> get selectedIds => List.unmodifiable(_selectedIds);
  bool get isLoaded => _loaded;

  bool isSectionVisible(HomeSection section) =>
      !_hiddenSections.contains(section);

  String _prefsKey(String companyId) => 'homeQuickActions_v1_$companyId';
  String _sectionsKey(String companyId) => 'homeHiddenSections_v1_$companyId';

  /// Call when the active company changes (e.g. after login or company switch).
  Future<void> setCompanyId(String companyId) async {
    if (companyId.isEmpty) return;
    if (companyId == _companyId && _loaded) return;

    _companyId = companyId;
    _loaded = false;
    _selectedIds = List.from(HomeActionsRegistry.defaultActionIds);
    _hiddenSections = Set.of(defaultHiddenSections);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey(companyId));
    if (saved != null) {
      // A saved list is the user's own choice and is used exactly as saved.
      // Missing defaults used to be appended back up to six on every cold
      // start, so an action someone removed reappeared the next day.
      _selectedIds = saved
          .where((id) => HomeActionsRegistry.getById(id) != null)
          .take(HomeActionsRegistry.maxActions)
          .toList();
    }
    final savedSections = prefs.getStringList(_sectionsKey(companyId));
    if (savedSections != null) {
      _hiddenSections = {
        for (final name in savedSections)
          for (final s in HomeSection.values)
            if (s.name == name) s,
      };
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

  Future<void> setSectionVisible(HomeSection section, bool visible) async {
    if (_companyId.isEmpty) return;
    final next = {..._hiddenSections};
    visible ? next.remove(section) : next.add(section);
    _hiddenSections = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _sectionsKey(_companyId),
      next.map((s) => s.name).toList(),
    );
  }

  Future<void> resetToDefaults() async {
    if (_companyId.isEmpty) return;
    _selectedIds = List.from(HomeActionsRegistry.defaultActionIds);
    _hiddenSections = Set.of(defaultHiddenSections);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey(_companyId));
    await prefs.remove(_sectionsKey(_companyId));
  }

  void reset() {
    _companyId = '';
    _selectedIds = List.from(HomeActionsRegistry.defaultActionIds);
    _hiddenSections = Set.of(defaultHiddenSections);
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

  /// Whether [action] can be used by the user [vis] describes: its permission,
  /// its workspace switches, and — through the feature catalog — the plan and
  /// any module an admin switched off. Quick actions checked only the first
  /// two, so a plan-locked or switched-off feature stayed on Home.
  static bool isActionAvailable(HomeAction action, FeatureVisibility vis) {
    if (action.permissionKey != null && !vis.has(action.permissionKey!)) {
      return false;
    }
    if (!satisfiesFeatureGates(
      action,
      billingEnabled: vis.gates.billing,
      barcodeEnabled: vis.gates.barcode,
      vendorsEnabled: vis.gates.vendors,
      pricingEnabled: vis.gates.pricing,
    )) {
      return false;
    }
    final entry = FeatureMap.getById(action.featureId);
    return entry == null || vis.allows(entry);
  }

  /// The selected actions the user can actually use, in their saved order.
  List<HomeAction> visibleActions(FeatureVisibility vis) => [
    for (final id in _selectedIds)
      if (HomeActionsRegistry.getById(id) case final action?)
        if (isActionAvailable(action, vis)) action,
  ];
}
