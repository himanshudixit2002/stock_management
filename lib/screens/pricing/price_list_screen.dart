import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/price_list_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/price_list_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Customer price lists — what a given customer actually pays.
class PriceListScreen extends StatefulWidget {
  const PriceListScreen({super.key});

  @override
  State<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends State<PriceListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<PriceListProvider>().initialize(companyId: companyId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewPriceLists,
      featureName: 'Price Lists',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<PriceListProvider>();
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.managePriceLists) ??
          false,
    );

    return AppScreenScaffold(
      icon: Icons.sell_rounded,
      title: 'Price Lists',
      subtitle: '${provider.active.length} active',
      iconColor: AppTheme.successColor,
      isLoading: provider.isLoading && provider.lists.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.priceListEditor),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New list'),
            )
          : null,
      isEmpty: provider.lists.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.sell_rounded,
        title: 'No price lists yet',
        subtitle:
            'Wholesale and retail share one selling price today. A price list '
            'gives a group of customers their own, without editing the '
            'catalog.',
        buttonText: canManage ? 'Create a price list' : null,
        onButtonPressed: canManage
            ? () => context.pushAppRoute(AppRoutes.priceListEditor)
            : null,
      ),
      body: Column(
        children: [
          if (provider.errorMessage != null)
            ProviderErrorBanner(
              message: provider.errorMessage!,
              onDismiss: provider.clearError,
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: provider.lists.length,
              itemBuilder: (context, i) {
                final list = provider.lists[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PriceListCard(
                    list: list,
                    index: i,
                    onTap: canManage
                        ? () => context.pushAppRoute(
                            AppRoutes.priceListEditor,
                            extra: list,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceListCard extends StatelessWidget {
  const _PriceListCard({
    required this.list,
    required this.index,
    this.onTap,
  });

  final PriceListModel list;
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final applicable = list.isApplicable;
    final color = applicable ? AppTheme.successColor : AppTheme.textMuted;

    return AnimatedListItem(
      index: index,
      child: GlassCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      list.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      list.isExpired
                          ? 'Expired'
                          : (list.isActive ? 'Active' : 'Off'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              if (list.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  list.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSec(context),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _Chip(
                    icon: Icons.percent_rounded,
                    label: list.defaultDiscountPercent > 0
                        ? '${list.defaultDiscountPercent.toStringAsFixed(1)}% off catalog'
                        : 'No blanket discount',
                  ),
                  _Chip(
                    icon: Icons.inventory_2_rounded,
                    label: '${list.entries.length} product prices',
                  ),
                  _Chip(
                    icon: Icons.people_rounded,
                    label: '${list.customerIds.length} customers',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tint = AppTheme.textSec(context);
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
