import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/register_session_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/register_session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/register_tally_service.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/not_found_state.dart';
import '../../widgets/permission_gate.dart';

/// One shift: its cash movements, and the blind close.
class RegisterSessionDetailScreen extends StatefulWidget {
  const RegisterSessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<RegisterSessionDetailScreen> createState() =>
      _RegisterSessionDetailScreenState();
}

class _RegisterSessionDetailScreenState
    extends State<RegisterSessionDetailScreen> {
  static final DateFormat _timeFormat = DateFormat('dd MMM, HH:mm');

  /// Set once the operator has entered their count on an open shift. Until
  /// then the expected figure is deliberately hidden: a count taken with the
  /// answer on screen is a confirmation, not a count.
  double? _counted;

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

  Future<void> _recordMovement(RegisterSessionModel session) async {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    var isPayout = true;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
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
                'Cash in or out',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Out'),
                    icon: Icon(Icons.arrow_upward_rounded),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('In'),
                    icon: Icon(Icons.arrow_downward_rounded),
                  ),
                ],
                selected: {isPayout},
                onSelectionChanged: (values) =>
                    setSheet(() => isPayout = values.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Safe drop, petty cash, float top-up…',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetCtx, true),
                  child: const Text('Record'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final amount = double.tryParse(amountController.text.trim()) ?? 0;
    final reason = reasonController.text.trim();
    amountController.dispose();
    reasonController.dispose();
    if (confirmed != true || !mounted || amount <= 0) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<RegisterSessionProvider>();
    final ok = await provider.recordCashMovement(
      session: session,
      amount: isPayout ? -amount : amount,
      reason: reason,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Cash movement recorded.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not record.');
    }
  }

  Future<void> _close(
    RegisterSessionModel session,
    RegisterTally tally,
  ) async {
    final counted = _counted;
    if (counted == null) return;

    final variance = tally.varianceFor(counted);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Close this shift?',
      message: variance.abs() < 0.01
          ? 'The drawer balances. Closing stamps the tally and frees the '
                'register for the next shift.'
          : 'The count is ${variance > 0 ? 'over' : 'short'} by '
                '${variance.abs().toStringAsFixed(2)}. Closing records that '
                'difference against this shift permanently.',
      confirmLabel: 'Close shift',
      icon: Icons.lock_rounded,
      iconColor: variance.abs() < 0.01
          ? AppTheme.successColor
          : AppTheme.warningColor,
    );
    if (!confirmed || !mounted) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<RegisterSessionProvider>();
    final ok = await provider.closeSession(
      session: session,
      countedCash: counted,
      tally: tally,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Shift closed.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not close.');
    }
  }

  Future<void> _askCount() async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Count the drawer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter what is physically in the drawer, notes and coins. The '
              'expected figure is revealed only after you commit to a number.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSec(ctx),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Counted cash'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Reveal'),
          ),
        ],
      ),
    );
    final value = double.tryParse((entered ?? '').trim());
    controller.dispose();
    if (value == null || !mounted) return;
    setState(() => _counted = value);
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
    final session = provider.byId(widget.sessionId);
    final symbol = Money.symbolOf(context);

    if (session == null) {
      return AppScreenScaffold(
        icon: Icons.savings_rounded,
        title: 'Shift',
        iconColor: AppTheme.infoColor,
        isLoading: provider.isLoading,
        body: const NotFoundState(
          icon: Icons.savings_rounded,
          title: 'Shift not found',
          message: 'It may have been deleted since this link was opened.',
        ),
      );
    }

    final invoices = context.watch<BillingProvider>().invoices;
    final tally = provider.tallyFor(session, invoices);
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageRegisterSessions) ??
          false,
    );
    // A closed shift shows what it counted; an open one hides the expected
    // figure until the operator has entered theirs.
    final revealed = !session.isOpen || _counted != null;
    final counted = session.isOpen ? _counted : session.countedCash;
    final expected = session.isOpen ? tally.expectedCash : session.expectedCash;
    final variance = (counted ?? 0) - expected;

    return AppScreenScaffold(
      icon: Icons.savings_rounded,
      title: session.registerName,
      subtitle: session.isOpen
          ? 'Open · ${session.duration.inHours}h so far'
          : 'Closed',
      iconColor: session.isOpen ? AppTheme.infoColor : AppTheme.successColor,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.isOpen ? 'Shift in progress' : 'Z-report',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                _Line(
                  label: 'Opening float',
                  value: Money.withSymbol(symbol, session.openingFloat),
                ),
                _Line(
                  label: 'Sales',
                  value: Money.withSymbol(
                    symbol,
                    session.isOpen ? tally.salesTotal : session.salesTotal,
                  ),
                  caption:
                      '${session.isOpen ? tally.invoiceCount : session.invoiceCount} invoices',
                ),
                _Line(
                  label: 'Cash taken',
                  value: Money.withSymbol(symbol, tally.cashTakings),
                ),
                _Line(
                  label: 'Other methods',
                  value: Money.withSymbol(symbol, tally.otherTakings),
                ),
                if (tally.creditSales > 0)
                  _Line(
                    label: 'On credit (not in the drawer)',
                    value: Money.withSymbol(symbol, tally.creditSales),
                  ),
                if (tally.refundTotal > 0)
                  _Line(
                    label: 'Refunded',
                    value: '-${Money.withSymbol(symbol, tally.refundTotal)}',
                  ),
                _Line(
                  label: 'Cash movements',
                  value: Money.withSymbol(symbol, tally.movementTotal),
                  caption: session.movements.isEmpty
                      ? null
                      : '${session.movements.length} recorded',
                ),
                const Divider(height: 20),
                if (revealed) ...[
                  _Line(
                    label: 'Expected in drawer',
                    value: Money.withSymbol(symbol, expected),
                    emphasise: true,
                  ),
                  _Line(
                    label: 'Counted',
                    value: Money.withSymbol(symbol, counted ?? 0),
                    emphasise: true,
                  ),
                  _Line(
                    label: variance.abs() < 0.01
                        ? 'Balanced'
                        : (variance > 0 ? 'Over by' : 'Short by'),
                    value: Money.withSymbol(symbol, variance.abs()),
                    emphasise: true,
                    color: variance.abs() < 0.01
                        ? AppTheme.successColor
                        : AppTheme.dangerColor,
                  ),
                ] else
                  Text(
                    'The expected figure appears once you have counted the '
                    'drawer. Counting against a number already on screen is a '
                    'confirmation, not a count.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSec(context),
                    ),
                  ),
              ],
            ),
          ),
          if (tally.takingsByMethod.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassSectionCard(
              title: 'By payment method',
              icon: Icons.payments_rounded,
              child: Column(
                children: [
                  for (final entry in tally.takingsByMethod.entries)
                    _Line(
                      label: entry.key,
                      value: Money.withSymbol(symbol, entry.value),
                    ),
                ],
              ),
            ),
          ],
          if (session.movements.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassSectionCard(
              title: 'Cash movements',
              icon: Icons.swap_vert_rounded,
              child: Column(
                children: [
                  for (final movement in session.movements)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  movement.reason.isEmpty
                                      ? (movement.isPayout
                                            ? 'Cash out'
                                            : 'Cash in')
                                      : movement.reason,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${_timeFormat.format(movement.at)} · '
                                  '${movement.userName}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textSec(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Money.withSymbol(symbol, movement.amount),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: movement.isPayout
                                  ? AppTheme.dangerColor
                                  : AppTheme.successColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (canManage && session.isOpen) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: provider.isBusy
                      ? null
                      : () => _recordMovement(session),
                  icon: const Icon(Icons.swap_vert_rounded),
                  label: const Text('Record cash in or out'),
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: provider.isBusy
                    ? null
                    : (_counted == null
                          ? _askCount
                          : () => _close(session, tally)),
                icon: Icon(
                  _counted == null
                      ? Icons.calculate_rounded
                      : Icons.lock_rounded,
                ),
                label: Text(
                  _counted == null ? 'Count the drawer' : 'Close the shift',
                ),
              ),
            ),
            if (_counted != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(
                  onPressed: () => setState(() => _counted = null),
                  child: const Text('Re-count'),
                ),
              ),
          ],
          if (!session.isOpen && session.closedAt != null)
            Text(
              'Closed ${_timeFormat.format(session.closedAt!)} by '
              '${session.closedByName.isEmpty ? 'someone' : session.closedByName}.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSec(context),
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.caption,
    this.emphasise = false,
    this.color,
  });

  final String label;
  final String value;
  final String? caption;
  final bool emphasise;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: emphasise ? 13.5 : 12.5,
                    fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
                    color: color ?? (emphasise ? null : AppTheme.textSec(context)),
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSec(context),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasise ? 15 : 13,
              fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
