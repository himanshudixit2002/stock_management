import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/home_actions.dart';
import '../../config/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/home_customization_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/shimmer_loading.dart';

class HomeCustomizationScreen extends StatefulWidget {
  const HomeCustomizationScreen({super.key});

  @override
  State<HomeCustomizationScreen> createState() =>
      _HomeCustomizationScreenState();
}

class _HomeCustomizationScreenState extends State<HomeCustomizationScreen> {
  late List<String> _selected;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _selected = List.from(
      context.read<HomeCustomizationProvider>().selectedIds,
    );
  }

  void _toggle(String id) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        if (_selected.length >= HomeActionsRegistry.maxActions) return;
        _selected.add(id);
      }
      _hasChanges = true;
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _selected.removeAt(oldIndex);
      _selected.insert(newIndex, item);
      _hasChanges = true;
    });
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      showInfoSnackBar(context, 'Please select at least one action');
      return;
    }
    await context.read<HomeCustomizationProvider>().saveActions(_selected);
    if (mounted) {
      showSuccessSnackBar(context, 'Home actions updated');
      Navigator.pop(context);
    }
  }

  void _reset() {
    HapticFeedback.mediumImpact();
    setState(() {
      _selected = List.from(HomeActionsRegistry.defaultActionIds);
      _hasChanges = true;
    });
  }

  String _gateDisplayName(HomeActionFeatureGate gate) {
    switch (gate) {
      case HomeActionFeatureGate.billing:
        return 'Billing';
      case HomeActionFeatureGate.barcode:
        return 'Barcode scanner';
      case HomeActionFeatureGate.vendors:
        return 'Vendors';
      case HomeActionFeatureGate.pricing:
        return 'Pricing';
    }
  }

  Future<void> _enableFeature(HomeActionFeatureGate gate) async {
    switch (gate) {
      case HomeActionFeatureGate.billing:
        final billing = context.read<BillingSettingsProvider>();
        final ok = await billing.toggleBilling(true);
        if (!mounted) return;
        if (!ok) {
          showErrorSnackBar(
            context,
            billing.errorMessage ?? 'Failed to enable billing',
          );
        }
      case HomeActionFeatureGate.barcode:
        final settings = context.read<SettingsProvider>();
        final ok = await settings.toggleBarcode(true);
        if (!mounted) return;
        if (!ok) {
          showErrorSnackBar(
            context,
            settings.errorMessage ?? 'Failed to update setting',
          );
        }
      case HomeActionFeatureGate.vendors:
        final settings = context.read<SettingsProvider>();
        final ok = await settings.toggleVendors(true);
        if (!mounted) return;
        if (!ok) {
          showErrorSnackBar(
            context,
            settings.errorMessage ?? 'Failed to update setting',
          );
        }
      case HomeActionFeatureGate.pricing:
        final settings = context.read<SettingsProvider>();
        final ok = await settings.togglePricing(true);
        if (!mounted) return;
        if (!ok) {
          showErrorSnackBar(
            context,
            settings.errorMessage ?? 'Failed to update setting',
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeCustomization = context.watch<HomeCustomizationProvider>();
    final perms =
        context.watch<AuthProvider>().currentUser?.effectivePermissions ??
        UserModel.defaultPermissions;
    final billingOn = context.watch<BillingSettingsProvider>().billingEnabled;
    final settings = context.watch<SettingsProvider>();
    final isAdmin = context.watch<AuthProvider>().currentUser?.isAdmin ?? false;

    final maxContentWidth = Responsive.isDesktop(context)
        ? Responsive.contentMaxWidth(context)
        : Responsive.formMaxWidth(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize Home'),
        actions: [
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Reset'),
          ),
        ],
      ),
      body: SafeArea(
        child: !homeCustomization.isLoaded
            ? Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: const ShimmerLoading(layout: ShimmerLayout.listTile),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            Responsive.horizontalPadding(context),
                            12,
                            Responsive.horizontalPadding(context),
                            24,
                          ),
                          children: [
                            _buildSelectedSection(),
                            const SizedBox(height: 20),
                            _buildAvailableSection(
                              perms,
                              billingEnabled: billingOn,
                              barcodeEnabled: settings.barcodeEnabled,
                              vendorsEnabled: settings.vendorsEnabled,
                              pricingEnabled: settings.pricingEnabled,
                              isAdmin: isAdmin,
                            ),
                          ],
                        ),
                      ),
                      _buildBottomBar(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildSelectedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'SELECTED ACTIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.iconMute(context),
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _selected.length >= HomeActionsRegistry.maxActions
                      ? AppTheme.warningColor.withValues(alpha: 0.15)
                      : AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_selected.length} / ${HomeActionsRegistry.maxActions}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _selected.length >= HomeActionsRegistry.maxActions
                        ? AppTheme.warningColor
                        : AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_selected.isEmpty)
          GlassPanel(
            borderRadius: 14,
            useContentVariant: true,
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    size: 36,
                    color: AppTheme.iconMute(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap actions below to add them here',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textTer(context),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          GlassPanel(
            borderRadius: 14,
            useContentVariant: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _selected.length,
                onReorder: _reorder,
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) => Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.transparent,
                      child: child,
                    ),
                    child: child,
                  );
                },
                itemBuilder: (context, index) {
                  final action = HomeActionsRegistry.getById(_selected[index]);
                  if (action == null)
                    return const SizedBox.shrink(key: ValueKey('empty'));
                  return _SelectedTile(
                    key: ValueKey(action.id),
                    action: action,
                    index: index,
                    onRemove: () => _toggle(action.id),
                  );
                },
              ),
            ),
          ),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Long press and drag to reorder',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textMuted.withValues(alpha: 0.7),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvailableSection(
    Map<String, bool> perms, {
    required bool billingEnabled,
    required bool barcodeEnabled,
    required bool vendorsEnabled,
    required bool pricingEnabled,
    required bool isAdmin,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AVAILABLE ACTIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.iconMute(context),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth > 500 ? 4 : 3;
            final spacing = 10.0;
            final itemWidth =
                (constraints.maxWidth - spacing * (crossCount - 1)) /
                crossCount;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: HomeActionsRegistry.allActions.map((action) {
                final isSelected = _selected.contains(action.id);
                final hasPermission =
                    action.permissionKey == null ||
                    perms[action.permissionKey] == true;
                final featuresOk =
                    HomeCustomizationProvider.satisfiesFeatureGates(
                      action,
                      billingEnabled: billingEnabled,
                      barcodeEnabled: barcodeEnabled,
                      vendorsEnabled: vendorsEnabled,
                      pricingEnabled: pricingEnabled,
                    );
                final blockedGate = hasPermission && !featuresOk
                    ? HomeCustomizationProvider.firstUnsatisfiedFeatureGate(
                        action,
                        billingEnabled: billingEnabled,
                        barcodeEnabled: barcodeEnabled,
                        vendorsEnabled: vendorsEnabled,
                        pricingEnabled: pricingEnabled,
                      )
                    : null;
                final isFull =
                    _selected.length >= HomeActionsRegistry.maxActions;
                final canToggle =
                    isSelected || (hasPermission && featuresOk && !isFull);
                return SizedBox(
                  width: itemWidth,
                  child: _AvailableActionCard(
                    action: action,
                    isSelected: isSelected,
                    hasPermission: hasPermission,
                    featuresOk: featuresOk,
                    blockedGate: blockedGate,
                    isAdmin: isAdmin,
                    isDisabled: !isSelected && isFull,
                    gateDisplayName: _gateDisplayName,
                    onTap: canToggle ? () => _toggle(action.id) : null,
                    onEnableFeature: blockedGate != null && isAdmin
                        ? () => _enableFeature(blockedGate)
                        : null,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        12,
        Responsive.horizontalPadding(context),
        12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(
          top: BorderSide(color: AppTheme.dividerC(context), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _hasChanges ? _save : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.primaryColor.withValues(
                alpha: 0.4,
              ),
              disabledForegroundColor: Colors.white70,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: _hasChanges ? 2 : 0,
            ),
            child: const Text(
              'Save Changes',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedTile extends StatelessWidget {
  final HomeAction action;
  final int index;
  final VoidCallback onRemove;

  const _SelectedTile({
    super.key,
    required this.action,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: AppTheme.iconMute(context),
                  size: 20,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: action.gradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(action.icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                action.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: AppTheme.dangerColor.withValues(alpha: 0.7),
              ),
              onPressed: onRemove,
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailableActionCard extends StatelessWidget {
  final HomeAction action;
  final bool isSelected;
  final bool hasPermission;
  final bool featuresOk;
  final HomeActionFeatureGate? blockedGate;
  final bool isAdmin;
  final bool isDisabled;
  final String Function(HomeActionFeatureGate) gateDisplayName;
  final VoidCallback? onTap;
  final Future<void> Function()? onEnableFeature;

  const _AvailableActionCard({
    required this.action,
    required this.isSelected,
    required this.hasPermission,
    required this.featuresOk,
    required this.blockedGate,
    required this.isAdmin,
    required this.isDisabled,
    required this.gateDisplayName,
    this.onTap,
    this.onEnableFeature,
  });

  @override
  Widget build(BuildContext context) {
    final permissionLocked = !hasPermission;
    final featureLocked = hasPermission && !featuresOk;
    final slotBlocked = isDisabled && !isSelected;
    final dimForSelection = permissionLocked || slotBlocked;
    final opacity = dimForSelection ? 0.4 : (featureLocked ? 0.92 : 1.0);

    final borderColor = isSelected
        ? Colors.transparent
        : featureLocked
        ? AppTheme.warningColor.withValues(alpha: 0.55)
        : dimForSelection
        ? AppTheme.dividerC(context).withValues(alpha: 0.5)
        : AppTheme.dividerC(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        gradient: isSelected ? action.gradient : null,
        color: isSelected
            ? null
            : featureLocked
            ? AppTheme.warningColor.withValues(alpha: 0.06)
            : dimForSelection
            ? AppTheme.surface(context).withValues(alpha: 0.5)
            : AppTheme.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: action.gradient.colors.first.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dimForSelection ? null : onTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.2)
                              : action.gradient.colors.first.withValues(
                                  alpha: 0.1,
                                ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          action.icon,
                          size: 22,
                          color: isSelected
                              ? Colors.white
                              : action.gradient.colors.first,
                        ),
                      ),
                      if (permissionLocked)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppTheme.surface(context),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.lock_rounded,
                              size: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                      if (featureLocked)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppTheme.surface(context),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.extension_off_outlined,
                              size: 10,
                              color: AppTheme.warningColor,
                            ),
                          ),
                        ),
                      if (isSelected)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              size: 12,
                              color: AppTheme.successColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    action.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: isSelected
                          ? Colors.white
                          : AppTheme.textPri(context),
                    ),
                  ),
                ],
              ),
            ),
            if (featureLocked && blockedGate != null)
              _FeatureGateFooter(
                gate: blockedGate!,
                isAdmin: isAdmin,
                isSelected: isSelected,
                gateDisplayName: gateDisplayName,
                onEnableFeature: onEnableFeature,
              ),
          ],
        ),
      ),
    );
  }
}

class _FeatureGateFooter extends StatelessWidget {
  final HomeActionFeatureGate gate;
  final bool isAdmin;
  final bool isSelected;
  final String Function(HomeActionFeatureGate) gateDisplayName;
  final Future<void> Function()? onEnableFeature;

  const _FeatureGateFooter({
    required this.gate,
    required this.isAdmin,
    required this.isSelected,
    required this.gateDisplayName,
    this.onEnableFeature,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Text(
          isAdmin
              ? '${gateDisplayName(gate)} is off'
              : 'Ask an admin to enable ${gateDisplayName(gate)} in Settings → Features.',
          textAlign: TextAlign.center,
          maxLines: isAdmin ? 1 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            height: 1.25,
            color: isSelected
                ? Colors.white.withValues(alpha: 0.9)
                : AppTheme.textTer(context),
          ),
        ),
        if (isAdmin && onEnableFeature != null) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 30,
            child: FilledButton.tonal(
              onPressed: () => onEnableFeature!(),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Enable ${gateDisplayName(gate)}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
