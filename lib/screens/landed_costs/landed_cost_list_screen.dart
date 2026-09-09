import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/landed_cost_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/landed_cost_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/currency.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Freight, duty and handling sheets, and the cost prices they set.
class LandedCostListScreen extends StatefulWidget {
  const LandedCostListScreen({super.key});

  @override
  State<LandedCostListScreen> createState() => _LandedCostListScreenState();
}

class _LandedCostListScreenState extends State<LandedCostListScreen> {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<LandedCostProvider>().initialize(companyId: companyId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewLandedCosts,
      featureName: 'Landed Costs',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<LandedCostProvider>();
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageLandedCosts) ??
          false,
    );
    final symbol = Money.symbolOf(context);

    return AppScreenScaffold(
      icon: Icons.local_shipping_outlined,
      title: 'Landed Costs',
      subtitle: '${provider.drafts.length} drafts',
      iconColor: AppTheme.warningColor,
      isLoading: provider.isLoading && provider.sheets.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () =>
                  context.pushAppRoute(AppRoutes.landedCostEditor),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New sheet'),
            )
          : null,
      isEmpty: provider.sheets.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.local_shipping_outlined,
        title: 'No landed cost sheets yet',
        subtitle:
            'Cost price is the supplier price today, so every margin report '
            'ignores what it cost to get the goods in. A sheet spreads freight '
            'and duty across the lines that carried them.',
        buttonText: canManage ? 'Create a sheet' : null,
        onButtonPressed: canManage
            ? () => context.pushAppRoute(AppRoutes.landedCostEditor)
            : null,
      ),
      body: Column(
        children: [
          if (provider.errorMessage != null)
            ProviderErrorBanner(
              message: provider.errorMessage!,
              onDismiss: provider.clearError,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: MetricCard(
              label: 'Charges captured',
              value: Money.withSymbol(symbol, provider.appliedCharges),
              icon: Icons.calculate_rounded,
              color: AppTheme.warningColor,
              caption: 'Across applied sheets — cost that used to disappear',
              index: 0,
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: provider.sheets.length,
              itemBuilder: (context, i) {
                final sheet = provider.sheets[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SheetCard(
                    sheet: sheet,
                    index: i,
                    symbol: symbol,
                    dateFormat: _dateFormat,
                    onTap: () => context.pushAppRoute(
                      AppRoutes.landedCostEditor,
                      extra: sheet,
                    ),
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

class _SheetCard extends StatelessWidget {
  const _SheetCard({
    required this.sheet,
    required this.index,
    required this.symbol,
    required this.dateFormat,
    this.onTap,
  });

  final LandedCostModel sheet;
  final int index;
  final String symbol;
  final DateFormat dateFormat;
  final VoidCallback? onTap;

  static Color statusColor(LandedCostStatus status) => switch (status) {
    LandedCostStatus.draft => AppTheme.warningColor,
    LandedCostStatus.applied => AppTheme.successColor,
    LandedCostStatus.reversed => AppTheme.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    final color = statusColor(sheet.status);
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
                      sheet.referenceNumber.isEmpty
                          ? (sheet.vendorName.isEmpty
                                ? 'Shipment ${dateFormat.format(sheet.shipmentDate)}'
                                : sheet.vendorName)
                          : sheet.referenceNumber,
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
                      sheet.statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  dateFormat.format(sheet.shipmentDate),
                  '${sheet.lines.length} line'
                      '${sheet.lines.length == 1 ? '' : 's'}',
                  if (sheet.purchaseOrderNumber.isNotEmpty)
                    'PO ${sheet.purchaseOrderNumber}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(context),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Goods',
                      value: Money.withSymbol(symbol, sheet.baseValue),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: 'Charges',
                      value: Money.withSymbol(symbol, sheet.totalCharges),
                      accent: AppTheme.warningColor,
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: 'Uplift',
                      value: '${sheet.upliftPercent.toStringAsFixed(1)}%',
                      accent: sheet.upliftPercent > 15
                          ? AppTheme.dangerColor
                          : null,
                    ),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.accent});

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppTheme.textSec(context)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
        ),
      ],
    );
  }
}
