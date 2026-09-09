import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/app_navigation.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/register_session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/provider_error_banner.dart';

/// Till shifts: what is open now, and what every past shift counted.
class RegisterSessionListScreen extends StatefulWidget {
  const RegisterSessionListScreen({super.key});

  @override
  State<RegisterSessionListScreen> createState() =>
      _RegisterSessionListScreenState();
}

class _RegisterSessionListScreenState extends State<RegisterSessionListScreen> {
  static final DateFormat _dateFormat = DateFormat('dd MMM, HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final companyId = context.read<SettingsProvider>().companyId;
      if (companyId.isNotEmpty) {
        context.read<RegisterSessionProvider>().initialize(
          companyId: companyId,
        );
      }
    });
  }

  Future<void> _openShift() async {
    final registers = context.read<SettingsProvider>().locations;
    final nameController = TextEditingController(
      text: registers.isNotEmpty ? registers.first : 'Main',
    );
    final floatController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open a shift',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'The float is what is in the drawer before the first sale. It is '
              'what the close is measured against.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSec(sheetCtx),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Register'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: floatController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Opening float'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(sheetCtx, true),
                child: const Text('Open shift'),
              ),
            ),
          ],
        ),
      ),
    );

    final registerName = nameController.text.trim();
    final float = double.tryParse(floatController.text.trim()) ?? 0;
    nameController.dispose();
    floatController.dispose();
    if (confirmed != true || !mounted) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<RegisterSessionProvider>();
    final session = await provider.openSession(
      registerName: registerName,
      openingFloat: float,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
    );
    if (!mounted) return;
    if (session != null) {
      showSuccessSnackBar(context, '${session.registerName} is open.');
    } else {
      showErrorSnackBar(
        context,
        provider.errorMessage ?? 'Could not open the shift.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewRegisterSessions,
      featureName: 'Register Shifts',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final provider = context.watch<RegisterSessionProvider>();
    final invoices = context.watch<BillingProvider>().invoices;
    final symbol = Money.symbolOf(context);
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageRegisterSessions) ??
          false,
    );

    final open = provider.openSessions;
    final closed = provider.sessions.where((s) => !s.isOpen).toList();
    final shortfalls = closed.where((s) => s.variance < -0.01).length;

    return AppScreenScaffold(
      icon: Icons.savings_rounded,
      title: 'Register Shifts',
      subtitle: open.isEmpty ? 'No shift open' : '${open.length} open',
      iconColor: AppTheme.infoColor,
      isLoading: provider.isLoading && provider.sessions.isEmpty,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _openShift,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Open shift'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (provider.errorMessage != null)
            ProviderErrorBanner(
              message: provider.errorMessage!,
              onDismiss: provider.clearError,
            ),
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Open shifts',
                  value: '${open.length}',
                  icon: Icons.lock_open_rounded,
                  color: AppTheme.infoColor,
                  dense: true,
                  index: 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'Short closes',
                  value: '$shortfalls',
                  icon: Icons.report_gmailerrorred_rounded,
                  color: shortfalls == 0
                      ? AppTheme.successColor
                      : AppTheme.dangerColor,
                  caption: 'Of ${closed.length} counted',
                  dense: true,
                  index: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (open.isNotEmpty) ...[
            Text(
              'Open now',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSec(context),
              ),
            ),
            const SizedBox(height: 8),
            for (final session in open)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  onTap: () => context.pushAppRoute(
                    AppRoutes.registerSessionDetail,
                    extra: session.id,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                session.registerName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              Money.withSymbol(
                                symbol,
                                provider
                                    .tallyFor(session, invoices)
                                    .expectedCash,
                              ),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Opened ${_dateFormat.format(session.openedAt)} by '
                          '${session.openedByName.isEmpty ? 'someone' : session.openedByName}'
                          ' · float ${Money.withSymbol(symbol, session.openingFloat)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (closed.isEmpty && open.isEmpty)
            EmptyStateWidget(
              icon: Icons.savings_rounded,
              title: 'No shifts yet',
              subtitle:
                  'Open a shift with the float that is in the drawer. Every '
                  'sale rung up on Fast POS is stamped with it, so the close '
                  'can tell you what should be there.',
              buttonText: canManage ? 'Open shift' : null,
              onButtonPressed: canManage ? _openShift : null,
            )
          else if (closed.isNotEmpty) ...[
            Text(
              'History',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSec(context),
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < closed.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AnimatedListItem(
                  index: i,
                  child: GlassCard(
                    onTap: () => context.pushAppRoute(
                      AppRoutes.registerSessionDetail,
                      extra: closed[i].id,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  closed[i].registerName,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${_dateFormat.format(closed[i].openedAt)}'
                                  '${closed[i].closedAt == null ? '' : ' → ${_dateFormat.format(closed[i].closedAt!)}'}'
                                  ' · ${closed[i].invoiceCount} sales',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSec(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Money.withSymbol(symbol, closed[i].countedCash),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                closed[i].isBalanced
                                    ? 'Balanced'
                                    : '${closed[i].variance > 0 ? 'Over' : 'Short'} '
                                          '${Money.withSymbol(symbol, closed[i].variance.abs())}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: closed[i].isBalanced
                                      ? AppTheme.successColor
                                      : AppTheme.dangerColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
