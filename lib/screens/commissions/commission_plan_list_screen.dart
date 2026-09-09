import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/commission_plan_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/commission_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// The commission schemes a workspace runs.
class CommissionPlanListScreen extends StatefulWidget {
  const CommissionPlanListScreen({super.key});

  @override
  State<CommissionPlanListScreen> createState() =>
      _CommissionPlanListScreenState();
}

class _CommissionPlanListScreenState extends State<CommissionPlanListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<CommissionProvider>().initialize(companyId: companyId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewCommissions,
      featureName: 'Commission Plans',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<CommissionProvider>();
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageCommissions) ??
          false,
    );

    return AppScreenScaffold(
      icon: Icons.percent_rounded,
      title: 'Commission Plans',
      subtitle: '${provider.activePlans.length} active',
      iconColor: AppTheme.violetColor,
      isLoading: provider.isLoading && provider.plans.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () =>
                  context.pushAppRoute(AppRoutes.commissionPlanEditor),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New plan'),
            )
          : null,
      isEmpty: provider.plans.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.percent_rounded,
        title: 'No commission plans',
        subtitle:
            'A plan names a basis, a rate, and who it applies to. A plan '
            'naming nobody applies to everybody, which is usually what a '
            'single house scheme wants.',
        buttonText: canManage ? 'Create a plan' : null,
        onButtonPressed: canManage
            ? () => context.pushAppRoute(AppRoutes.commissionPlanEditor)
            : null,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: provider.plans.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return provider.errorMessage == null
                ? const SizedBox.shrink()
                : ProviderErrorBanner(
                    message: provider.errorMessage!,
                    onDismiss: provider.clearError,
                  );
          }
          final plan = provider.plans[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AnimatedListItem(
              index: index - 1,
              child: GlassCard(
                onTap: canManage
                    ? () => context.pushAppRoute(
                        AppRoutes.commissionPlanEditor,
                        extra: plan,
                      )
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              plan.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${plan.defaultPercent.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        [
                          CommissionPlanModel.basisLabelOf(plan.basis),
                          plan.appliesToEveryone
                              ? 'everyone'
                              : '${plan.userIds.length} people',
                          if (plan.categoryRates.isNotEmpty)
                            '${plan.categoryRates.length} category rates',
                          plan.includeUnpaid
                              ? 'paid on issue'
                              : 'paid on collection',
                          if (!plan.isActive) 'inactive',
                        ].join(' · '),
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 12,
                          color: plan.isActive
                              ? AppTheme.textSec(context)
                              : AppTheme.dangerColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
