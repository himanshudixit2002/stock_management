import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/feature_access.dart';
import '../../config/feature_visibility.dart';
import '../../config/home_actions.dart';
import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/home_customization_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/success_overlay.dart';

class HomeCustomizationScreen extends StatefulWidget {
  const HomeCustomizationScreen({super.key, this.focusId});

  /// Accepted so a settings search hit can route here like any other page.
  /// The screen is a single list, so there is nothing finer to scroll to.
  final String? focusId;

  @override
  State<HomeCustomizationScreen> createState() =>
      _HomeCustomizationScreenState();
}

class _HomeCustomizationScreenState extends State<HomeCustomizationScreen> {
  late List<String> _selected;
  late Set<HomeSection> _hiddenSections;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final layout = context.read<HomeCustomizationProvider>();
    _selected = List.from(layout.selectedIds);
    _hiddenSections = {
      for (final section in HomeSection.values)
        if (!layout.isSectionVisible(section)) section,
    };
  }

  void _setSectionVisible(HomeSection section, bool visible) {
    HapticFeedback.selectionClick();
    setState(() {
      visible ? _hiddenSections.remove(section) : _hiddenSections.add(section);
      _hasChanges = true;
    });
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
    final layout = context.read<HomeCustomizationProvider>();
    if (_selected.isEmpty &&
        !_hiddenSections.contains(HomeSection.quickActions)) {
      showInfoSnackBar(
        context,
        'Pick at least one action, or switch Quick actions off',
      );
      return;
    }
    await layout.saveActions(_selected);
    for (final section in HomeSection.values) {
      final visible = !_hiddenSections.contains(section);
      if (layout.isSectionVisible(section) != visible) {
        await layout.setSectionVisible(section, visible);
      }
    }
    if (!mounted) return;
    setState(() => _hasChanges = false);
    showSuccessOverlay(context, message: 'Home updated');
  }

  void _reset() {
    HapticFeedback.mediumImpact();
    setState(() {
      _selected = List.from(HomeActionsRegistry.defaultActionIds);
      _hiddenSections = Set.of(
        HomeCustomizationProvider.defaultHiddenSections,
      );
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
    final vis = FeatureVisibility.watch(context);
    final isAdmin = context.watch<AuthProvider>().currentUser?.isAdmin ?? false;

    final maxContentWidth = Responsive.isDesktop(context)
        ? Responsive.contentMaxWidth(context)
        : Responsive.formMaxWidth(context);

    return AppScreenScaffold(
      icon: Icons.dashboard_customize_rounded,
      title: 'Customize Home',
      constrainWidth: false,
      isLoading: !homeCustomization.isLoaded,
      shimmerLayout: ShimmerLayout.listTile,
      actions: [
        TextButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: const Text('Reset'),
        ),
      ],
      bottomNavigationBar: homeCustomization.isLoaded ? _buildBottomBar() : null,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              Responsive.horizontalPadding(context),
              12,
              Responsive.horizontalPadding(context),
              24,
            ),
            children: [
              _buildSectionsSection(vis, isAdmin: isAdmin),
              if (!_hiddenSections.contains(HomeSection.quickActions)) ...[
                const SizedBox(height: 20),
                _buildSelectedSection(vis),
                const SizedBox(height: 20),
                _buildAvailableSection(
                  vis,
                  // The switches are company settings, so whoever may change
                  // those can turn one on from here, not only admins.
                  canManage: vis.has(AppPermissions.manageCompanySettings),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Sections this user could see at all. Getting started is an admin
  /// checklist, and the AI panel needs the plan and the report permission, so
  /// offering either switch to someone who never gets the section only
  /// confused them.
  List<HomeSection> _sectionsFor(
    FeatureVisibility vis, {
    required bool isAdmin,
  }) => [
    for (final section in HomeSection.values)
      if (switch (section) {
        HomeSection.gettingStarted => isAdmin,
        HomeSection.aiInsights =>
          vis.allowsId('aiAssistant') && vis.has(AppPermissions.viewReports),
        _ => true,
      })
        section,
  ];

  Widget _buildSectionsSection(FeatureVisibility vis, {required bool isAdmin}) {
    final sections = _sectionsFor(vis, isAdmin: isAdmin);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('HOME SECTIONS', AppTheme.infoColor),
        GlassPanel(
          borderRadius: 14,
          useContentVariant: true,
          child: Column(
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: AppTheme.dividerC(context)),
                _SectionSwitch(
                  info: HomeCustomizationProvider.sectionInfo[sections[i]]!,
                  value: !_hiddenSections.contains(sections[i]),
                  onChanged: (v) => _setSectionVisible(sections[i], v),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text, Color color, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSec(context),
                letterSpacing: 1.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildSelectedSection(FeatureVisibility vis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(
          'SELECTED ACTIONS',
          AppTheme.primaryColor,
          trailing: 
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
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _selected.length >= HomeActionsRegistry.maxActions
                        ? AppTheme.warningColor
                        : AppTheme.primaryColor,
                  ),
                ),
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
                  if (action == null) {
                    return const SizedBox.shrink(key: ValueKey('empty'));
                  }
                  return _SelectedTile(
                    key: ValueKey(action.id),
                    action: action,
                    index: index,
                    available: HomeCustomizationProvider.isActionAvailable(
                      action,
                      vis,
                    ),
                    onRemove: () => _toggle(action.id),
                  );
                },
              ),
            ),
          ),
        if (_selected.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              // The handle starts a drag straight away; there is no long press.
              'Drag the handle to reorder',
              style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
            ),
          ),
      ],
    );
  }

  /// Actions worth offering: ones the user can use now, plus — for someone
  /// who manages company settings — ones held back by a workspace switch,
  /// which they can turn on from the card. Actions behind a permission, the plan or a hidden module used to
  /// be listed too, padlocked, for people with no way to unlock them.
  Widget _buildAvailableSection(
    FeatureVisibility vis, {
    required bool canManage,
  }) {
    final offered = <(HomeAction, HomeActionFeatureGate?)>[];
    for (final action in HomeActionsRegistry.allActions) {
      if (HomeCustomizationProvider.isActionAvailable(action, vis)) {
        offered.add((action, null));
        continue;
      }
      if (!canManage) continue;
      final gate = HomeCustomizationProvider.firstUnsatisfiedFeatureGate(
        action,
        billingEnabled: vis.gates.billing,
        barcodeEnabled: vis.gates.barcode,
        vendorsEnabled: vis.gates.vendors,
        pricingEnabled: vis.gates.pricing,
      );
      // Only a switch is something the admin can fix from here.
      if (gate == null) continue;
      final withGateOn = FeatureVisibility(
        permissions: vis.permissions,
        gates: FeatureGateState(
          billing: true,
          barcode: true,
          vendors: true,
          pricing: true,
          hiddenFeatures: vis.gates.hiddenFeatures,
        ),
        plan: vis.plan,
      );
      if (HomeCustomizationProvider.isActionAvailable(action, withGateOn)) {
        offered.add((action, gate));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('AVAILABLE ACTIONS', AppTheme.accentColor),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth > 500 ? 4 : 3;
            const spacing = 10.0;
            final itemWidth =
                (constraints.maxWidth - spacing * (crossCount - 1)) /
                crossCount;
            final isFull = _selected.length >= HomeActionsRegistry.maxActions;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final (i, (action, blockedGate)) in offered.indexed)
                  SizedBox(
                    width: itemWidth,
                    child: FadeSlideIn(
                      index: i,
                      child: _AvailableActionCard(
                        action: action,
                        isSelected: _selected.contains(action.id),
                        hasPermission: true,
                        featuresOk: blockedGate == null,
                        blockedGate: blockedGate,
                        isAdmin: canManage,
                        isDisabled: !_selected.contains(action.id) && isFull,
                        gateDisplayName: _gateDisplayName,
                        onTap:
                            _selected.contains(action.id) ||
                                (blockedGate == null && !isFull)
                            ? () => _toggle(action.id)
                            : null,
                        onEnableFeature: blockedGate != null
                            ? () => _enableFeature(blockedGate)
                            : null,
                      ),
                    ),
                  ),
              ],
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
        child: Center(
          // Only as tall as the button: a bottom bar is offered the whole
          // screen's height, and an unbounded Center took all of it.
          heightFactor: 1,
          // The body is capped at a form width; a save button spanning a
          // 1440 px window sat far from everything it saved.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.formMaxWidth(context),
            ),
            child: ShimmerButton(
              label: 'Save Changes',
              icon: Icons.check_rounded,
              onPressed: _hasChanges ? _save : null,
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

  /// False when Home will skip this action for the current user.
  final bool available;
  final VoidCallback onRemove;

  const _SelectedTile({
    super.key,
    required this.action,
    required this.index,
    required this.available,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  if (!available)
                    Text(
                      'Not shown on Home: not available to you right now',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                ],
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
                      fontSize: 12,
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
              : 'Ask an admin to turn on ${gateDisplayName(gate)} in '
                    'Workspace features.',
          textAlign: TextAlign.center,
          maxLines: isAdmin ? 1 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
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
                  fontSize: 12,
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

/// One row of the Home sections list.
class _SectionSwitch extends StatelessWidget {
  const _SectionSwitch({
    required this.info,
    required this.value,
    required this.onChanged,
  });

  final HomeSectionInfo info;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      secondary: Icon(info.icon, color: AppTheme.primary(context)),
      title: Text(
        info.title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPri(context),
        ),
      ),
      subtitle: Text(
        info.subtitle,
        style: TextStyle(fontSize: 12, color: AppTheme.textSec(context)),
      ),
    );
  }
}
