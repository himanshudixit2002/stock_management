import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/feature_map.dart';
import '../../config/home_actions.dart' show HomeActionFeatureGate;
import '../../config/theme.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/app_list_row.dart';
import '../../widgets/app_screen_scaffold.dart';
import 'settings_context.dart';
import 'settings_focus.dart';
import 'settings_page_shell.dart';

/// The four company-wide feature switches.
///
/// Each one hides or reveals whole areas of the app for everybody in the
/// workspace, so each row names what it actually controls. Turning Vendors off
/// removes six destinations; the old screen said only "Enable Vendors" and left
/// people to discover the rest by their absence.
class SettingsFeaturesScreen extends StatefulWidget {
  const SettingsFeaturesScreen({super.key, this.focusId});

  final String? focusId;

  @override
  State<SettingsFeaturesScreen> createState() => _SettingsFeaturesScreenState();
}

class _SettingsFeaturesScreenState extends State<SettingsFeaturesScreen>
    with SettingsFocusMixin {
  bool _resolvedFocus = false;

  /// Destinations that disappear when [gate] is switched off, so the row can
  /// say so before it is flipped rather than after.
  String? _affects(HomeActionFeatureGate gate) {
    final labels = FeatureMap.all
        .where((e) => e.featureGates.contains(gate))
        .map((e) => e.label)
        .toList();
    // Null, not '': an empty string still renders a blank second line and
    // leaves the row taller than its neighbours for no reason.
    if (labels.isEmpty) return null;
    if (labels.length <= 3) return 'Controls ${labels.join(', ')}.';
    return 'Controls ${labels.take(3).join(', ')} '
        'and ${labels.length - 3} more.';
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolvedFocus) {
      _resolvedFocus = true;
      focusAfterLayout(widget.focusId ?? settingsAnchorOf(context));
    }

    final settings = context.watch<SettingsProvider>();
    final billing = context.watch<BillingSettingsProvider>();
    final ctx = settingsVisibilityContext(context);
    final readOnly = isInspectingWorkspace(context);

    String error() => settings.errorMessage ?? 'Failed to update setting';

    return AppScreenScaffold(
      icon: Icons.toggle_on_rounded,
      title: 'Workspace features',
      subtitle: 'Applies to everyone in this workspace',
      iconColor: AppTheme.infoColor,
      body: SettingsPageBody(
        children: [
          if (readOnly)
            const SettingsNote(
              text: kInspectionReadOnlyNote,
              icon: Icons.visibility_rounded,
              color: AppTheme.warningColor,
            ),
          SettingsGroup(
            title: 'Workspace switches',
            subtitle: 'Turning one off hides it for every member',
            children: [
              if (canSee('features.pricing', ctx))
                KeyedSubtree(
                  key: keyFor('features.pricing'),
                  child: AppSwitchRow(
                    icon: Icons.attach_money_rounded,
                    accent: AppTheme.successColor,
                    title: 'Pricing',
                    subtitle:
                        'Show cost and selling prices on products and reports',
                    value: settings.pricingEnabled,
                    enabled: !readOnly,
                    highlighted: isFlashing('features.pricing'),
                    errorText: error,
                    onChanged: settings.togglePricing,
                  ),
                ),
              if (canSee('features.vendors', ctx))
                KeyedSubtree(
                  key: keyFor('features.vendors'),
                  child: AppSwitchRow(
                    index: 1,
                    icon: Icons.local_shipping_rounded,
                    accent: AppTheme.indigoColor,
                    title: 'Vendors',
                    subtitle: _affects(HomeActionFeatureGate.vendors),
                    value: settings.vendorsEnabled,
                    enabled: !readOnly,
                    highlighted: isFlashing('features.vendors'),
                    errorText: error,
                    onChanged: settings.toggleVendors,
                  ),
                ),
              if (canSee('features.barcode', ctx))
                KeyedSubtree(
                  key: keyFor('features.barcode'),
                  child: AppSwitchRow(
                    index: 2,
                    icon: Icons.qr_code_scanner_rounded,
                    accent: AppTheme.infoColor,
                    title: 'Barcode scanner',
                    subtitle: _affects(HomeActionFeatureGate.barcode),
                    value: settings.barcodeEnabled,
                    enabled: !readOnly,
                    highlighted: isFlashing('features.barcode'),
                    errorText: error,
                    onChanged: settings.toggleBarcode,
                  ),
                ),
              if (canSee('features.billing', ctx))
                KeyedSubtree(
                  key: keyFor('features.billing'),
                  child: AppSwitchRow(
                    index: 3,
                    icon: Icons.point_of_sale_rounded,
                    accent: AppTheme.successColor,
                    title: 'Billing',
                    subtitle: _affects(HomeActionFeatureGate.billing),
                    value: billing.billingEnabled,
                    enabled: !readOnly,
                    highlighted: isFlashing('features.billing'),
                    errorText: () => 'Failed to update setting',
                    onChanged: billing.toggleBilling,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
