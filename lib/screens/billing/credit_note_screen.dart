import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/invoice_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../utils/currency.dart';
import '../../utils/date_formats.dart';
import '../../utils/dialogs.dart';
import '../../widgets/success_overlay.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/glass_panel.dart';

/// Raises a credit note against an invoice, reducing its outstanding balance.
///
/// This is the supported way to unwind money on an invoice that has taken
/// payment: cancelling one is blocked because cancelled documents drop out of
/// both invoiced and received totals, so the cash would vanish from reports.
class CreditNoteScreen extends StatefulWidget {
  const CreditNoteScreen({super.key, required this.invoice});

  final InvoiceModel invoice;

  @override
  State<CreditNoteScreen> createState() => _CreditNoteScreenState();
}

class _CreditNoteScreenState extends State<CreditNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _saving = false;

  /// The most that may be credited: the invoice total less what has already
  /// been paid and less any credit already raised.
  double get _creditable {
    final inv = widget.invoice;
    final left = inv.grandTotal - inv.amountPaid - inv.creditedAmount;
    return left < 0 ? 0 : left;
  }

  @override
  void initState() {
    super.initState();
    _amountController.text = _creditable.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      showErrorSnackBar(context, 'Please sign in again to continue.');
      return;
    }

    final amount = double.parse(_amountController.text.trim());
    final billing = context.read<BillingProvider>();
    final bs = context.read<BillingSettingsProvider>().settings;

    setState(() => _saving = true);

    final number = await billing.getNextInvoiceNumber(
      '${bs.invoicePrefix}-CN',
      // Its own sequence, so issuing a credit note no longer punches a hole in
      // the sales-invoice series.
      type: InvoiceType.creditNote,
    );
    if (!mounted) return;
    if (number == null) {
      setState(() => _saving = false);
      showErrorSnackBar(
        context,
        billing.errorMessage ?? 'Could not generate a credit note number.',
      );
      return;
    }

    final now = DateTime.now();
    final source = widget.invoice;
    final note = InvoiceModel(
      id: '',
      invoiceType: InvoiceType.creditNote,
      invoiceNumber: number,
      customerId: source.customerId,
      customerName: source.customerName,
      customerPhone: source.customerPhone,
      customerAddress: source.customerAddress,
      status: InvoiceStatus.sent,
      subtotal: amount,
      grandTotal: amount,
      amountDue: 0,
      notes: _reasonController.text.trim(),
      invoiceDate: now,
      dueDate: now,
      createdBy: user.uid,
      createdByName: user.name,
      createdAt: now,
      updatedAt: now,
    );

    final id = await billing.issueCreditNote(
      sourceInvoiceId: source.id,
      creditNote: note,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    if (id == null) {
      showErrorSnackBar(
        context,
        billing.errorMessage ?? 'Failed to issue credit note.',
      );
      return;
    }
    await showSuccessOverlay(context, message: 'Credit note $number issued');
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final creditable = _creditable;

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.receipt_rounded,
          color: AppTheme.warningColor,
          title: 'Credit Note',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassPanel(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inv.invoiceNumber,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${inv.partyName} • ${AppDates.day.format(inv.invoiceDate)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Divider(height: 20),
                      _Row(label: 'Invoice total', value: inv.grandTotal),
                      _Row(label: 'Already paid', value: inv.amountPaid),
                      if (inv.creditedAmount > 0)
                        _Row(
                          label: 'Already credited',
                          value: inv.creditedAmount,
                        ),
                      _Row(
                        label: 'Available to credit',
                        value: creditable,
                        emphasise: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (creditable <= 0)
                Text(
                  'This invoice has nothing left to credit. Its balance is '
                  'already fully paid or credited.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.warningColor,
                  ),
                )
              else ...[
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Credit amount',
                    prefixIcon: Icon(Icons.payments_rounded),
                  ),
                  validator: (v) {
                    final parsed = double.tryParse((v ?? '').trim());
                    if (parsed == null) return 'Enter a valid amount';
                    if (parsed <= 0) return 'Amount must be greater than zero';
                    if (parsed > creditable + 0.01) {
                      return 'Cannot exceed ${Money.of(context, creditable)}';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Give a reason for this credit'
                      : null,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Issuing…' : 'Issue Credit Note'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final double value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          Text(
            Money.of(context, value),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
              color: emphasise ? AppTheme.primaryColor : null,
            ),
          ),
        ],
      ),
    );
  }
}
