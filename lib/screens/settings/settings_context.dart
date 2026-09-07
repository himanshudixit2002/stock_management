import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/feature_access.dart';
import '../../config/settings_catalog.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/settings_provider.dart';

/// Builds the visibility context the catalog reasons about, from the providers.
///
/// One place so the hub, all six sub-pages and search agree on what the current
/// user can see. Permissions come from `currentUser.effectivePermissions`,
/// which is `allTrue()` for an admin and, during a super-admin inspection, the
/// synthetic viewer's — so an inspector sees the workspace as its own members
/// do rather than as themselves.
SettingsVisibilityContext settingsVisibilityContext(BuildContext context) {
  final user = context.watch<AuthProvider>().currentUser;
  final settings = context.watch<SettingsProvider>();
  final billing = context.watch<BillingSettingsProvider>();

  return SettingsVisibilityContext(
    permissions: user?.effectivePermissions ?? UserModel.defaultPermissions,
    gates: FeatureGateState(
      billing: billing.billingEnabled,
      barcode: settings.barcodeEnabled,
      vendors: settings.vendorsEnabled,
      pricing: settings.pricingEnabled,
    ),
    isWeb: kIsWeb,
    // Only once the company document has actually arrived. Before that the
    // plan falls back to a default whose locked features would briefly hide
    // rows and then bring them back a frame later.
    plan: settings.isInitialized ? settings.plan : null,
  );
}

/// True while a super-admin is inspecting someone else's workspace.
///
/// Writes are refused in that mode, so every settings control that saves has to
/// say so rather than failing silently when tapped.
bool isInspectingWorkspace(BuildContext context) =>
    context.watch<AuthProvider>().isInspecting;

/// The banner text shown above controls that cannot be used right now.
const String kInspectionReadOnlyNote =
    'You are inspecting this workspace. Settings here are read-only.';
