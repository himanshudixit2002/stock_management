import 'feature_map.dart';
import 'home_actions.dart' show HomeActionFeatureGate;

/// Why a catalogued feature is or is not reachable by a given user.
///
/// [FeatureMap.isVisible] answers the same question as a bool, which is all the
/// navigation needs. Explaining a feature to a user needs the reason as well:
/// "ask an admin" and "switch it on for the workspace" are different problems
/// with different fixes, and a greyed row with neither just prompts a support
/// message.
enum FeatureAccess {
  available,

  /// The user's role does not grant the feature's permission key.
  needsPermission,

  /// A company-level feature switch that this feature depends on is off.
  featureOff,
}

/// The company-level feature switches, as one value.
class FeatureGateState {
  const FeatureGateState({
    this.billing = false,
    this.barcode = true,
    this.vendors = true,
    this.pricing = true,
  });

  final bool billing;
  final bool barcode;
  final bool vendors;
  final bool pricing;

  bool isOn(HomeActionFeatureGate gate) => switch (gate) {
    HomeActionFeatureGate.billing => billing,
    HomeActionFeatureGate.barcode => barcode,
    HomeActionFeatureGate.vendors => vendors,
    HomeActionFeatureGate.pricing => pricing,
  };

  /// Human label for a gate, used to name the exact switch that is off.
  static String labelOf(HomeActionFeatureGate gate) => switch (gate) {
    HomeActionFeatureGate.billing => 'Billing',
    HomeActionFeatureGate.barcode => 'Barcode',
    HomeActionFeatureGate.vendors => 'Vendors',
    HomeActionFeatureGate.pricing => 'Pricing',
  };

  /// Gates [entry] depends on that are currently off.
  List<HomeActionFeatureGate> blockedGatesFor(FeatureEntry entry) =>
      entry.featureGates.where((g) => !isOn(g)).toList();
}

/// Resolves how [entry] stands for a user holding [permissions].
///
/// Gates are checked before permissions on purpose: when a feature is switched
/// off for the whole workspace, that is the useful thing to say, even if the
/// user also lacks the permission. Telling them to ask for access to something
/// nobody can currently use would send them down the wrong path.
FeatureAccess resolveFeatureAccess(
  FeatureEntry entry,
  Map<String, bool> permissions,
  FeatureGateState gates,
) {
  if (gates.blockedGatesFor(entry).isNotEmpty) return FeatureAccess.featureOff;
  if (entry.permissionKey != null && permissions[entry.permissionKey] != true) {
    return FeatureAccess.needsPermission;
  }
  return FeatureAccess.available;
}
