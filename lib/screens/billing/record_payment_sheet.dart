import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../models/invoice_model.dart';
import '../../providers/billing_provider.dart';
import '../../utils/dialogs.dart';

class RecordPaymentSheet extends StatefulWidget {
  final String invoiceId;
  final String? invoiceNumber;
  final double amountDue;
  final String currencySymbol;

  const RecordPaymentSheet({
    super.key,
    required this.invoiceId,
    this.invoiceNumber,
    required this.amountDue,
    this.currencySymbol = '₹',
  });

  @override
  State<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _method = 'cash';
  DateTime _date = DateTime.now();
  bool _isSaving = false;

  static const _methods = [
    ('cash', 'Cash', Icons.payments_rounded),
    ('upi', 'UPI', Icons.phone_android_rounded),
    ('card', 'Card', Icons.credit_card_rounded),
    ('bank', 'Bank Transfer', Icons.account_balance_rounded),
    ('cheque', 'Cheque', Icons.description_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: widget.amountDue.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount <= 0) return;
    if (amount > widget.amountDue + 0.01) {
      showInfoSnackBar(context, 'Amount cannot exceed amount due');
      return;
    }

    setState(() => _isSaving = true);

    final payment = PaymentRecord(
      id: const Uuid().v4(),
      amount: amount,
      date: _date,
      method: _method,
      referenceNumber: _refCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
    );

    final billing = context.read<BillingProvider>();
    final ok = await billing.recordPayment(widget.invoiceId, payment);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      showSuccessSnackBar(
        context,
        'Payment of ${widget.currencySymbol}${_amountCtrl.text} recorded',
      );
      Navigator.pop(context);
    } else {
      showErrorSnackBar(
        context,
        billing.errorMessage ?? 'Payment failed',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sym = widget.currencySymbol.isNotEmpty ? widget.currencySymbol : '₹';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.dividerC(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Record Payment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              if (widget.invoiceNumber != null &&
                  widget.invoiceNumber!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    widget.invoiceNumber!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                ),
              Text(
                'Amount due: $sym${NumberFormat('#,##0.00').format(widget.amountDue)}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSec(context),
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _amountCtrl,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '$sym ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  final amt = double.tryParse(v ?? '');
                  if (amt == null || amt <= 0) return 'Enter a valid amount';
                  if (amt > widget.amountDue + 0.01)
                    return 'Cannot exceed amount due';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Payment Method',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSec(context),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _methods.map((m) {
                  final selected = _method == m.$1;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          m.$3,
                          size: 16,
                          color: selected
                              ? Colors.white
                              : AppTheme.textSec(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          m.$2,
                          style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? Colors.white
                                : AppTheme.textPri(context),
                          ),
                        ),
                      ],
                    ),
                    selected: selected,
                    selectedColor: AppTheme.primaryColor,
                    onSelected: (_) => setState(() => _method = m.$1),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _refCtrl,
                      decoration: InputDecoration(
                        labelText: 'Reference # (optional)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null && mounted)
                        setState(() => _date = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.dividerC(context)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: AppTheme.textTer(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd MMM').format(_date),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Record Payment',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
