import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/recurring_invoice_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/recurring_invoice_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Recurring billing schedules, and the button that issues what they owe.
class RecurringInvoiceListScreen extends StatefulWidget {
  const RecurringInvoiceListScreen({super.key});

  @override
  State<RecurringInvoiceListScreen> createState() =>
      _RecurringInvoiceListScreenState();
}

class _RecurringInvoiceListScreenState
    extends State<RecurringInvoiceListScreen> {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<RecurringInvoiceProvider>().initialize(
          companyId: companyId,
        );
      }
    });
  }

  Future<void> _generateAll() async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final provider = context.read<RecurringInvoiceProvider>();
    final due = provider.due;
    final symbol = Money.symbolOf(context);

    final confirmed = await showConfirmDialog(
      context,
      title: 'Generate ${due.length} invoice${due.length == 1 ? '' : 's'}?',
      message:
          'Totalling ${Money.withSymbol(symbol, provider.dueValue)}. Each '
          'schedule advances to its next date, so pressing this twice cannot '
          'bill anyone twice.',
      confirmLabel: 'Generate',
      icon: Icons.autorenew_rounded,
      iconColor: AppTheme.infoColor,
      confirmColor: AppTheme.infoColor,
    );
    if (!confirmed || !mounted) return;

    final prefix = context.read<BillingSettingsProvider>().settings.invoicePrefix;
    final result = await provider.generateAllDue(
      invoicePrefix: prefix,
      userId: user.uid,
      userName: user.name,
    );
    if (!mounted) return;

    if (result.count == 0 && result.isClean) {
      showInfoSnackBar(context, 'Nothing was due after all.');
      return;
    }
    if (result.isClean) {
      showSuccessSnackBar(
        context,
        'Generated ${result.count} invoice${result.count == 1 ? '' : 's'}.',
      );
    } else {
      // Named, not counted: the operator has to know which customer was not
      // billed this cycle.
      showErrorSnackBar(
        context,
        'Generated ${result.count}. Failed: '
        '${result.failures.keys.take(3).join(', ')}.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewRecurringInvoices,
      featureName: 'Billing Schedules',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<RecurringInvoiceProvider>();
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(
            AppPermissions.manageRecurringInvoices,
          ) ??
          false,
    );
    final symbol = Money.symbolOf(context);
    final due = provider.due;

    return AppScreenScaffold(
      icon: Icons.event_repeat_rounded,
      title: 'Billing Schedules',
      subtitle: '${provider.schedules.length} schedules',
      iconColor: AppTheme.infoColor,
      isLoading: provider.isLoading && provider.schedules.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () =>
                  context.pushAppRoute(AppRoutes.recurringInvoiceEditor),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New schedule'),
            )
          : null,
      isEmpty: provider.schedules.isEmpty && !provider.isLoading,
      emptyState: EmptyStateWidget(
        icon: Icons.event_repeat_rounded,
        title: 'No billing schedules yet',
        subtitle:
            'Set a customer, some lines and a cadence once, then issue the '
            'invoice each cycle in a tap instead of re-keying it.',
        buttonText: canManage ? 'Create a schedule' : null,
        onButtonPressed: canManage
            ? () => context.pushAppRoute(AppRoutes.recurringInvoiceEditor)
            : null,
      ),
      body: Column(
        children: [
          if (provider.errorMessage != null)
            ProviderErrorBanner(
              message: provider.errorMessage!,
              onDismiss: provider.clearError,
            ),
          if (due.isNotEmpty && canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: GlassPanel(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: AppTheme.warningColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${due.length} schedule${due.length == 1 ? '' : 's'} due',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            Money.withSymbol(symbol, provider.dueValue),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.textSec(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: provider.isBusy ? null : _generateAll,
                      child: const Text('Generate'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: provider.schedules.length,
              itemBuilder: (context, i) {
                final schedule = provider.schedules[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ScheduleCard(
                    schedule: schedule,
                    index: i,
                    symbol: symbol,
                    canManage: canManage,
                    dateFormat: _dateFormat,
                    onTap: canManage
                        ? () => context.pushAppRoute(
                            AppRoutes.recurringInvoiceEditor,
                            extra: schedule,
                          )
                        : null,
                    onTogglePause: canManage
                        ? () => provider.setStatus(
                            schedule,
                            schedule.status == RecurringInvoiceStatus.paused
                                ? RecurringInvoiceStatus.active
                                : RecurringInvoiceStatus.paused,
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

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.index,
    required this.symbol,
    required this.canManage,
    required this.dateFormat,
    this.onTap,
    this.onTogglePause,
  });

  final RecurringInvoiceModel schedule;
  final int index;
  final String symbol;
  final bool canManage;
  final DateFormat dateFormat;
  final VoidCallback? onTap;
  final VoidCallback? onTogglePause;

  @override
  Widget build(BuildContext context) {
    final due = schedule.isDue();
    final days = schedule.daysUntilDue();
    final color = switch (schedule.status) {
      RecurringInvoiceStatus.active =>
        due ? AppTheme.warningColor : AppTheme.successColor,
      RecurringInvoiceStatus.paused => AppTheme.textMuted,
      RecurringInvoiceStatus.ended => AppTheme.textMuted,
    };

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
                      schedule.title.isEmpty
                          ? schedule.customerName
                          : schedule.title,
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
                      due ? 'Due now' : schedule.statusLabel,
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
                  schedule.cadenceLabel,
                  Money.withSymbol(
                    symbol,
                    RecurringInvoiceProvider.totalOf(schedule),
                  ),
                  '${schedule.items.length} line'
                      '${schedule.items.length == 1 ? '' : 's'}',
                  if (schedule.generatedCount > 0)
                    '${schedule.generatedCount} issued',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(context),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.event_rounded,
                    size: 14,
                    color: AppTheme.textSec(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      schedule.status == RecurringInvoiceStatus.ended
                          ? 'Ended'
                          : 'Next ${dateFormat.format(schedule.nextRunAt)}'
                                '${days < 0 ? ' (${-days} days overdue)' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  ),
                  if (canManage &&
                      schedule.status != RecurringInvoiceStatus.ended)
                    IconButton(
                      onPressed: onTogglePause,
                      icon: Icon(
                        schedule.status == RecurringInvoiceStatus.paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                      ),
                      tooltip:
                          schedule.status == RecurringInvoiceStatus.paused
                          ? 'Resume'
                          : 'Pause',
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
