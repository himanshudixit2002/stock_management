import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/quotation_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/quotation_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/currency.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// The sales pipeline: everything offered, and what came of it.
class QuotationListScreen extends StatefulWidget {
  const QuotationListScreen({super.key});

  @override
  State<QuotationListScreen> createState() => _QuotationListScreenState();
}

class _QuotationListScreenState extends State<QuotationListScreen> {
  QuotationStatus? _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<QuotationProvider>().initialize(companyId: companyId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewQuotations,
      featureName: 'Quotations',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<QuotationProvider>();
    final symbol = Money.symbolOf(context);
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageQuotations) ?? false,
    );

    final quotations = _filter == null
        ? provider.quotations
        : provider.quotations
              .where((q) => q.effectiveStatus == _filter)
              .toList();

    return AppScreenScaffold(
      icon: Icons.request_quote_rounded,
      title: 'Quotations',
      subtitle: '${provider.open.length} awaiting an answer',
      iconColor: AppTheme.indigoColor,
      isLoading: provider.isLoading && provider.quotations.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.pushAppRoute(AppRoutes.quotationEditor),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New quote'),
            )
          : null,
      isEmpty: provider.quotations.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.request_quote_rounded,
        title: 'No quotations yet',
        subtitle:
            'A quotation is the offer before the order: priced, dated, and '
            'convertible into a sales order the moment the customer says yes.',
        buttonText: canManage ? 'Raise a quote' : null,
        onButtonPressed: canManage
            ? () => context.pushAppRoute(AppRoutes.quotationEditor)
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
            child: Row(
              children: [
                Expanded(
                  child: MetricCard(
                    label: 'In play',
                    value: Money.compactWithSymbol(
                      symbol,
                      provider.pipelineValue,
                    ),
                    icon: Icons.trending_up_rounded,
                    color: AppTheme.indigoColor,
                    caption: '${provider.open.length} open',
                    dense: true,
                    index: 0,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    label: 'Win rate',
                    value: '${(provider.winRate * 100).round()}%',
                    icon: Icons.emoji_events_rounded,
                    color: AppTheme.successColor,
                    caption: 'Of quotes answered',
                    dense: true,
                    index: 1,
                  ),
                ),
              ],
            ),
          ),
          if (provider.expiringSoon.isNotEmpty || provider.lapsed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: GlassPanel(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 18,
                      color: AppTheme.warningColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        [
                          if (provider.expiringSoon.isNotEmpty)
                            '${provider.expiringSoon.length} quote(s) lapse within a week',
                          if (provider.lapsed.isNotEmpty)
                            '${provider.lapsed.length} already past their validity date',
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                for (final status in QuotationStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(QuotationModel.statusLabelOf(status)),
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
              itemCount: quotations.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: QuotationCard(
                  quotation: quotations[i],
                  index: i,
                  symbol: symbol,
                  onTap: () => context.pushAppRoute(
                    AppRoutes.quotationDetail,
                    extra: quotations[i].id,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One quotation, summarised.
class QuotationCard extends StatelessWidget {
  const QuotationCard({
    super.key,
    required this.quotation,
    required this.index,
    required this.symbol,
    this.onTap,
  });

  final QuotationModel quotation;
  final int index;
  final String symbol;
  final VoidCallback? onTap;

  static final DateFormat _dateFormat = DateFormat('dd MMM');

  static Color statusColor(QuotationStatus status) => switch (status) {
    QuotationStatus.draft => AppTheme.textMuted,
    QuotationStatus.sent => AppTheme.infoColor,
    QuotationStatus.accepted => AppTheme.successColor,
    QuotationStatus.declined => AppTheme.dangerColor,
    QuotationStatus.expired => AppTheme.warningColor,
    QuotationStatus.converted => AppTheme.violetColor,
  };

  @override
  Widget build(BuildContext context) {
    final status = quotation.effectiveStatus;
    final color = statusColor(status);
    final days = quotation.daysToExpiry;

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
                      quotation.customerName.isEmpty
                          ? 'No customer'
                          : quotation.customerName,
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
                      quotation.statusLabel,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        if (quotation.quoteNumber.isNotEmpty)
                          quotation.quoteNumber,
                        '${quotation.lines.length} line${quotation.lines.length == 1 ? '' : 's'}',
                        '${quotation.totalUnits} units',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ),
                  Text(
                    Money.withSymbol(symbol, quotation.grandTotal),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (quotation.validUntil != null &&
                  quotation.status == QuotationStatus.sent) ...[
                const SizedBox(height: 8),
                Text(
                  quotation.hasLapsed
                      ? 'Lapsed ${_dateFormat.format(quotation.validUntil!)}'
                      : 'Valid until ${_dateFormat.format(quotation.validUntil!)}'
                            '${days != null && days <= 7 ? ' · $days day${days == 1 ? '' : 's'} left' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: quotation.hasLapsed
                        ? AppTheme.warningColor
                        : AppTheme.textSec(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
