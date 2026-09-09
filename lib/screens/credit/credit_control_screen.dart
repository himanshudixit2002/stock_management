import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/customer_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/customer_provider.dart';
import '../../services/credit_control_service.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/permission_gate.dart';

/// Who owes what, against the credit you gave them.
class CreditControlScreen extends StatefulWidget {
  const CreditControlScreen({super.key});

  @override
  State<CreditControlScreen> createState() => _CreditControlScreenState();
}

class _CreditControlScreenState extends State<CreditControlScreen> {
  CreditVerdict? _filter;

  Future<void> _editTerms(CustomerModel customer) async {
    final limitController = TextEditingController(
      text: customer.creditLimit == 0
          ? ''
          : customer.creditLimit.toStringAsFixed(0),
    );
    final termsController = TextEditingController(
      text: customer.paymentTermDays == 0
          ? ''
          : '${customer.paymentTermDays}',
    );
    var hold = customer.creditHold;

    final saved = await showModalBottomSheet<bool>(
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
              Text(
                customer.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'A limit of zero means no limit is set — it does not stop '
                'credit sales.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(sheetCtx),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: limitController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Credit limit'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: termsController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Payment terms (days)',
                  helperText: 'Blank uses the workspace default',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: hold,
                onChanged: (value) => setSheet(() => hold = value),
                title: const Text('Credit hold'),
                subtitle: const Text('Refuses further credit whatever the limit'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetCtx, true),
                  child: const Text('Save terms'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final limit = double.tryParse(limitController.text.trim()) ?? 0;
    final terms = int.tryParse(termsController.text.trim()) ?? 0;
    limitController.dispose();
    termsController.dispose();
    if (saved != true || !mounted) return;

    final provider = context.read<CustomerProvider>();
    final ok = await provider.updateCustomer(
      customer.copyWith(
        creditLimit: limit,
        paymentTermDays: terms,
        creditHold: hold,
        updatedAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Credit terms updated.');
    } else {
      showErrorSnackBar(context, 'Could not update the credit terms.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewCreditControl,
      featureName: 'Credit Control',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final customers = context.watch<CustomerProvider>().customers;
    final invoices = context.watch<BillingProvider>().invoices;
    final symbol = Money.symbolOf(context);
    final canManage = context.select<AuthProvider, bool>(
      (a) =>
          a.currentUser?.hasPermission(AppPermissions.manageCreditLimits) ??
          false,
    );

    final book = CreditControlService.book(
      customers: customers,
      invoices: invoices,
    );
    final exposures = _filter == null
        ? book.exposures
        : book.exposures.where((e) => e.verdict == _filter).toList();

    return AppScreenScaffold(
      icon: Icons.credit_score_rounded,
      title: 'Credit Control',
      subtitle: '${book.exposures.length} accounts carrying credit',
      iconColor: AppTheme.violetColor,
      isEmpty: book.exposures.isEmpty,
      emptyState: const EmptyStateWidget(
        icon: Icons.credit_score_rounded,
        title: 'Nobody is on credit',
        subtitle:
            'Once a customer has an unpaid invoice or a credit limit, their '
            'exposure is tracked here — and checked at the invoice screen and '
            'the till before the next credit sale.',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: MetricCard(
                  label: 'Owed',
                  value: Money.compactWithSymbol(symbol, book.totalOutstanding),
                  icon: Icons.account_balance_rounded,
                  color: AppTheme.violetColor,
                  caption:
                      '${Money.compactWithSymbol(symbol, book.totalOverdue)} overdue',
                  dense: true,
                  index: 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  label: 'Blocked',
                  value: '${book.blockedCount}',
                  icon: Icons.block_rounded,
                  color: book.blockedCount == 0
                      ? AppTheme.successColor
                      : AppTheme.dangerColor,
                  caption: '${book.warningCount} to watch',
                  dense: true,
                  index: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
                for (final verdict in CreditVerdict.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(CreditControlService.verdictLabel(verdict)),
                      selected: _filter == verdict,
                      onSelected: (_) => setState(
                        () => _filter = _filter == verdict ? null : verdict,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < exposures.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AnimatedListItem(
                index: i,
                child: _ExposureCard(
                  exposure: exposures[i],
                  symbol: symbol,
                  onEdit: canManage
                      ? () {
                          final idx = customers.indexWhere(
                            (c) => c.id == exposures[i].customerId,
                          );
                          if (idx != -1) _editTerms(customers[idx]);
                        }
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExposureCard extends StatelessWidget {
  const _ExposureCard({
    required this.exposure,
    required this.symbol,
    this.onEdit,
  });

  final CreditExposure exposure;
  final String symbol;
  final VoidCallback? onEdit;

  static Color verdictColor(CreditVerdict verdict) => switch (verdict) {
    CreditVerdict.ok => AppTheme.successColor,
    CreditVerdict.warning => AppTheme.warningColor,
    CreditVerdict.blocked => AppTheme.dangerColor,
  };

  @override
  Widget build(BuildContext context) {
    final color = verdictColor(exposure.verdict);
    final utilisation = exposure.utilisation;

    return GlassCard(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exposure.customerName.isEmpty
                        ? 'Unnamed customer'
                        : exposure.customerName,
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
                    CreditControlService.verdictLabel(exposure.verdict),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    exposure.hasLimit
                        ? '${Money.withSymbol(symbol, exposure.outstanding)} of '
                              '${Money.withSymbol(symbol, exposure.creditLimit)}'
                        : '${Money.withSymbol(symbol, exposure.outstanding)} owed · no limit set',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (exposure.openInvoices > 0)
                  Text(
                    '${exposure.openInvoices} open',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSec(context),
                    ),
                  ),
              ],
            ),
            if (utilisation != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: utilisation > 1 ? 1 : utilisation,
                  minHeight: 5,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
            if (exposure.reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                exposure.reason,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
            if (exposure.overdueAmount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${Money.withSymbol(symbol, exposure.overdueAmount)} overdue'
                  '${exposure.oldestOverdueDays > 0 ? ' · oldest ${exposure.oldestOverdueDays} days' : ''}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSec(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
