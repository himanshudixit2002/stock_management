import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/bom_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/bom_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';
import 'build_assembly_sheet.dart';

/// Assembly recipes, and the entry point to building from them.
class BomListScreen extends StatefulWidget {
  const BomListScreen({super.key});

  @override
  State<BomListScreen> createState() => _BomListScreenState();
}

class _BomListScreenState extends State<BomListScreen> {
  BomStatus? _filter;

  @override
  void initState() {
    super.initState();
    // This provider is not started with the rest at sign-in — only this screen
    // and the build sheet read it, so opening its listener for every session
    // would buy nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<BomProvider>().initialize(companyId: companyId);
      }
    });
  }

  Future<void> _delete(BomModel bom) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete "${bom.name}"?',
      message:
          'The recipe goes; the stock movements it has already made stay on '
          'the ledger.',
    );
    if (!confirmed || !mounted) return;
    final ok = await context.read<BomProvider>().deleteBom(bom.id);
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Deleted "${bom.name}".');
    } else {
      showErrorSnackBar(
        context,
        context.read<BomProvider>().errorMessage ?? 'Delete failed.',
      );
    }
  }

  Future<void> _build(BomModel bom, {bool reverse = false}) async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;
    await showResponsiveBottomSheet<void>(
      context: context,
      builder: (_) => BuildAssemblySheet(
        bom: bom,
        reverse: reverse,
        userId: user.uid,
        userName: user.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewBoms,
      featureName: 'Bills of Materials',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<BomProvider>();
    final canManage = context.select<AuthProvider, bool>(
      (a) => a.currentUser?.hasPermission(AppPermissions.manageBoms) ?? false,
    );
    final canBuild = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.buildAssemblies) ?? false,
    );

    final boms = _filter == null
        ? provider.boms
        : provider.boms.where((b) => b.status == _filter).toList();

    return AppScreenScaffold(
      icon: Icons.account_tree_rounded,
      title: 'Bills of Materials',
      subtitle: '${provider.boms.length} recipes',
      iconColor: AppTheme.violetColor,
      isLoading: provider.isLoading && provider.boms.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.bomEditor),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New BOM'),
            )
          : null,
      isEmpty: provider.boms.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.account_tree_rounded,
        title: 'No bills of materials yet',
        subtitle:
            'Define what a finished product is made of, then build it in one '
            'step instead of two manual stock movements.',
        buttonText: canManage ? 'Create the first one' : null,
        onButtonPressed: canManage
            ? () => context.pushAppRoute(AppRoutes.bomEditor)
            : null,
      ),
      body: Column(
        children: [
          if (provider.errorMessage != null)
            ProviderErrorBanner(
              message: provider.errorMessage!,
              onDismiss: provider.clearError,
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final status in BomStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(switch (status) {
                        BomStatus.draft => 'Draft',
                        BomStatus.active => 'Active',
                        BomStatus.archived => 'Archived',
                      }),
                      selected: _filter == status,
                      onSelected: (_) => setState(
                        () => _filter = _filter == status ? null : status,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: boms.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BomCard(
                  bom: boms[i],
                  index: i,
                  canManage: canManage,
                  canBuild: canBuild,
                  onEdit: () => context.pushAppRoute(
                    AppRoutes.bomEditor,
                    extra: boms[i],
                  ),
                  onDelete: () => _delete(boms[i]),
                  onBuild: () => _build(boms[i]),
                  onUnbuild: () => _build(boms[i], reverse: true),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BomCard extends StatelessWidget {
  const _BomCard({
    required this.bom,
    required this.index,
    required this.canManage,
    required this.canBuild,
    required this.onEdit,
    required this.onDelete,
    required this.onBuild,
    required this.onUnbuild,
  });

  final BomModel bom;
  final int index;
  final bool canManage;
  final bool canBuild;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onBuild;
  final VoidCallback onUnbuild;

  Color _statusColor(BuildContext context) => switch (bom.status) {
    BomStatus.draft => AppTheme.textMute(context),
    BomStatus.active => AppTheme.successColor,
    BomStatus.archived => AppTheme.warningColor,
  };

  @override
  Widget build(BuildContext context) {
    // How many runs the current catalog could actually support, so the card can
    // say "you can build 12" rather than making the user open the sheet to
    // find out it is zero. Watched, not read: a build changes component stock,
    // and a card still advertising the old figure is worse than none.
    final available = {
      for (final product in context.watch<ProductProvider>().analyticsProducts)
        product.id: product.quantity,
    };
    final maxRuns = bom.maxRunsFrom(available);

    return AnimatedListItem(
      index: index,
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bom.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Makes ${bom.outputQuantity} × ${bom.outputProductName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSec(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(context).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    bom.statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _statusColor(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _Chip(
                  icon: Icons.category_rounded,
                  label: '${bom.components.length} components',
                ),
                _Chip(
                  icon: Icons.play_circle_outline_rounded,
                  label: maxRuns > 0
                      ? '$maxRuns run${maxRuns == 1 ? '' : 's'} possible'
                      : 'Not enough stock',
                  color: maxRuns > 0
                      ? AppTheme.successColor
                      : AppTheme.dangerColor,
                ),
                if (bom.totalBuilt > 0)
                  _Chip(
                    icon: Icons.history_rounded,
                    label: '${bom.totalBuilt} built to date',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (canBuild && bom.isBuildable) ...[
                  FilledButton.icon(
                    onPressed: maxRuns > 0 ? onBuild : null,
                    icon: const Icon(Icons.precision_manufacturing_rounded,
                        size: 16),
                    label: const Text('Build'),
                  ),
                  const SizedBox(width: 8),
                  if (bom.totalBuilt > 0)
                    OutlinedButton.icon(
                      onPressed: onUnbuild,
                      icon: const Icon(Icons.undo_rounded, size: 16),
                      label: const Text('Unbuild'),
                    ),
                ],
                const Spacer(),
                if (canManage) ...[
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: 'Delete',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppTheme.textSec(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: tint),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: tint)),
      ],
    );
  }
}
