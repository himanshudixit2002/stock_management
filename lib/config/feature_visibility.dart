import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/company_plan_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/billing_settings_provider.dart';
import '../providers/settings_provider.dart';
import 'feature_access.dart';
import 'feature_map.dart';

/// Everything that decides whether a catalogued feature is shown to the
/// signed-in user: their permissions, the workspace's switches and hidden
/// modules, and its plan.
///
/// Read from the providers in one place. Home, the tips, global search and the
/// alert scan each used to gather a different subset of these, so a module an
/// admin switched off, or one the plan does not include, kept turning up in
/// whichever surface had forgotten one of them.
class FeatureVisibility {
  const FeatureVisibility({
    required this.permissions,
    this.gates = const FeatureGateState(),
    this.plan,
  });

  final Map<String, bool> permissions;
  final FeatureGateState gates;
  final CompanyPlan? plan;

  /// Rebuilds the caller when any of the inputs change.
  factory FeatureVisibility.watch(BuildContext context) =>
      _fromProviders(context, listen: true);

  /// A one-off read, for callbacks and other non-build code.
  factory FeatureVisibility.read(BuildContext context) =>
      _fromProviders(context, listen: false);

  static FeatureVisibility _fromProviders(
    BuildContext context, {
    required bool listen,
  }) {
    final auth = Provider.of<AuthProvider>(context, listen: listen);
    final settings = Provider.of<SettingsProvider>(context, listen: listen);
    final billing = Provider.of<BillingSettingsProvider>(
      context,
      listen: listen,
    );
    return FeatureVisibility(
      permissions:
          auth.currentUser?.effectivePermissions ??
          UserModel.defaultPermissions,
      gates: FeatureGateState(
        billing: billing.billingEnabled,
        barcode: settings.barcodeEnabled,
        vendors: settings.vendorsEnabled,
        pricing: settings.pricingEnabled,
        hiddenFeatures: settings.hiddenFeatures,
      ),
      plan: settings.plan,
    );
  }

  bool has(String permission) => permissions[permission] == true;

  bool allows(FeatureEntry entry) => FeatureMap.isVisible(
    entry,
    permissions,
    billingEnabled: gates.billing,
    barcodeEnabled: gates.barcode,
    vendorsEnabled: gates.vendors,
    pricingEnabled: gates.pricing,
    plan: plan,
    hiddenFeatures: gates.hiddenFeatures,
  );

  /// Whether the catalogued feature [featureId] is shown. Unknown ids are not.
  bool allowsId(String featureId) {
    final entry = FeatureMap.getById(featureId);
    return entry != null && allows(entry);
  }

  /// Features whose name or description matches [query], best first: names
  /// that start with it, then names that contain it, then descriptions.
  ///
  /// Search-only tools such as Ageing, Payments and Landed Costs are reached
  /// this way and nowhere else, which global search did not use to cover.
  List<FeatureEntry> searchFeatures(String query, {int limit = 5}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    int rank(FeatureEntry e) {
      final label = e.label.toLowerCase();
      if (label.startsWith(q)) return 0;
      if (label.contains(q)) return 1;
      if (e.subtitle.toLowerCase().contains(q)) return 2;
      return -1;
    }

    final ranked = [
      for (final e in FeatureMap.all)
        // The assistant's entry has no screen of its own to open.
        if (e.id != 'aiAssistant' && rank(e) >= 0 && allows(e)) (rank(e), e),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, e) in ranked.take(limit)) e];
  }

  /// The shown entries of [category], optionally at one [placement].
  List<FeatureEntry> entriesIn(
    FeatureCategory category, {
    FeaturePlacement? placement,
  }) => FeatureMap.entriesByCategory(
    category,
    permissions,
    placement: placement,
    billingEnabled: gates.billing,
    barcodeEnabled: gates.barcode,
    vendorsEnabled: gates.vendors,
    pricingEnabled: gates.pricing,
    plan: plan,
    hiddenFeatures: gates.hiddenFeatures,
  );
}
