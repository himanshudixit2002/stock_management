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
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/not_found_state.dart';
import '../../widgets/permission_gate.dart';
import 'quotation_list_screen.dart' show QuotationCard;

/// One quotation, with the actions that move it along.
class QuotationDetailScreen extends StatefulWidget {
  const QuotationDetailScreen({super.key, required this.quotationId});

  final String quotationId;

  @override
  State<QuotationDetailScreen> createState() => _QuotationDetailScreenState();
}

class _QuotationDetailScreenState extends State<QuotationDetailScreen> {
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');

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

  Future<void> _send(QuotationModel quotation) async {
    final provider = context.read<QuotationProvider>();
    final ok = await provider.markSent(quotation);
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Marked as sent.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Could not update.');
    }
  }

  /// Asks for the decision note. Empty is allowed — a lost deal with no reason
  /// recorded is still worth recording as lost.
  Future<String?> _askNote({
    required String title,
    required String hint,
    required String confirmLabel,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _decide(QuotationModel quotation, bool accepted) async {
    final note = await _askNote(
      title: accepted ? 'Accept quotation' : 'Decline quotation',
      hint: accepted
          ? 'Any conditions the customer attached (optional)'
          : 'Why did they say no? (optional)',
      confirmLabel: accepted ? 'Accept' : 'Decline',
    );
    if (note == null || !mounted) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<QuotationProvider>();
    final ok = await provider.decide(
      quotation: quotation,
      accepted: accepted,
      note: note.trim(),
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
    );
    if (!mounted) return;
    if (ok) {
      showSuccessSnackBar(
        context,
        accepted ? 'Quotation accepted.' : 'Quotation declined.',
      );
    } else {
      showErrorSnackBar(
        context,
        provider.errorMessage ?? 'Could not record the decision.',
      );
    }
  }

  Future<void> _convert(QuotationModel quotation) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Convert to a sales order?',
      message:
          'This writes a draft sales order with the quoted lines and prices. '
          'The quotation is then closed as converted.',
      confirmLabel: 'Convert',
      icon: Icons.move_down_rounded,
      iconColor: AppTheme.violetColor,
    );
    if (!confirmed || !mounted) return;

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<QuotationProvider>();
    final orderId = await provider.convertToSalesOrder(
      quotation: quotation,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
    );
    if (!mounted) return;
    if (orderId == null) {
      showErrorSnackBar(
        context,
        provider.errorMessage ?? 'Could not convert this quotation.',
      );
      return;
    }
    showSuccessSnackBar(context, 'Sales order created.');
    context.pushAppRoute(AppRoutes.salesOrderDetail, extra: orderId);
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
    final quotation = provider.byId(widget.quotationId);
    final symbol = Money.symbolOf(context);

    if (quotation == null) {
      return AppScreenScaffold(
        icon: Icons.request_quote_rounded,
        title: 'Quotation',
        iconColor: AppTheme.indigoColor,
        isLoading: provider.isLoading,
        body: const NotFoundState(
          icon: Icons.request_quote_rounded,
          title: 'Quotation not found',
          message: 'It may have been deleted since this link was opened.',
        ),
      );
    }

    final user = context.watch<AuthProvider>().currentUser;
    final canManage =
        user?.hasPermission(AppPermissions.manageQuotations) ?? false;
    final canConvert =
        user?.hasPermission(AppPermissions.convertQuotations) ?? false;
    final busy = provider.isBusy;

    return AppScreenScaffold(
      icon: Icons.request_quote_rounded,
      title: quotation.quoteNumber.isEmpty
          ? 'Quotation'
          : quotation.quoteNumber,
      subtitle: quotation.customerName,
      iconColor: QuotationCard.statusColor(quotation.effectiveStatus),
      actions: [
        if (canManage && quotation.canEdit)
          IconButton(
            tooltip: 'Edit',
            onPressed: () => context.pushAppRoute(
              AppRoutes.quotationEditor,
              extra: quotation,
            ),
            icon: const Icon(Icons.edit_rounded),
          ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          GlassPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        quotation.statusLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: QuotationCard.statusColor(
                            quotation.effectiveStatus,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      Money.withSymbol(symbol, quotation.grandTotal),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Customer',
                  value: quotation.customerName.isEmpty
                      ? '—'
                      : quotation.customerName,
                ),
                if (quotation.validUntil != null)
                  _DetailRow(
                    label: 'Valid until',
                    value: _dateFormat.format(quotation.validUntil!),
                    warn: quotation.hasLapsed,
                  ),
                if (quotation.sentAt != null)
                  _DetailRow(
                    label: 'Sent',
                    value: _dateFormat.format(quotation.sentAt!),
                  ),
                if (quotation.decidedAt != null)
                  _DetailRow(
                    label: 'Answered',
                    value: _dateFormat.format(quotation.decidedAt!),
                  ),
                if (quotation.decisionNote.isNotEmpty)
                  _DetailRow(label: 'Note', value: quotation.decisionNote),
                if (quotation.convertedSalesOrderId.isNotEmpty)
                  _DetailRow(
                    label: 'Sales order',
                    value: quotation.convertedSalesOrderId,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassSectionCard(
            title: 'Lines',
            icon: Icons.inventory_2_rounded,
            child: Column(
              children: [
                for (final line in quotation.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${line.quantity} ${line.unit} × '
                                '${Money.withSymbol(symbol, line.unitPrice)}'
                                '${line.discountPercent > 0 ? ' · -${line.discountPercent.toStringAsFixed(0)}%' : ''}'
                                '${line.taxRate > 0 ? ' · ${line.taxRate.toStringAsFixed(0)}% tax' : ''}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.textSec(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          Money.withSymbol(symbol, line.total),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Tax',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                    Text(Money.withSymbol(symbol, quotation.totalTax)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      Money.withSymbol(symbol, quotation.grandTotal),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (quotation.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassSectionCard(
              title: 'Notes',
              icon: Icons.notes_rounded,
              child: Text(quotation.notes),
            ),
          ],
          const SizedBox(height: 16),
          if (canManage && quotation.canSend)
            _ActionButton(
              icon: Icons.send_rounded,
              label: 'Mark as sent',
              onPressed: busy ? null : () => _send(quotation),
            ),
          if (canManage && quotation.canDecide) ...[
            _ActionButton(
              icon: Icons.check_circle_rounded,
              label: 'Customer accepted',
              color: AppTheme.successColor,
              onPressed: busy ? null : () => _decide(quotation, true),
            ),
            _ActionButton(
              icon: Icons.cancel_rounded,
              label: 'Customer declined',
              color: AppTheme.dangerColor,
              onPressed: busy ? null : () => _decide(quotation, false),
            ),
          ],
          if (canConvert && quotation.canConvert)
            _ActionButton(
              icon: Icons.move_down_rounded,
              label: 'Convert to sales order',
              color: AppTheme.violetColor,
              onPressed: busy ? null : () => _convert(quotation),
            ),
          if (quotation.status == QuotationStatus.accepted && !canConvert)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'This quote is accepted. Converting it into a sales order needs '
                'the Convert Quotations permission.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSec(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.warn = false,
  });

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.textSec(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: warn ? AppTheme.warningColor : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: color == null
              ? null
              : FilledButton.styleFrom(backgroundColor: color),
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}
