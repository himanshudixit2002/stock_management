import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/expense_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/expense_provider.dart';
import '../../providers/vendor_provider.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/entity_picker_field.dart';
import '../../widgets/form_section.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/searchable_picker.dart';

/// Records or edits one operating expense.
class ExpenseEditorScreen extends StatefulWidget {
  const ExpenseEditorScreen({super.key, this.expense});

  final ExpenseModel? expense;

  @override
  State<ExpenseEditorScreen> createState() => _ExpenseEditorScreenState();
}

class _ExpenseEditorScreenState extends State<ExpenseEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _tax = TextEditingController();
  final _reference = TextEditingController();
  final _customCategory = TextEditingController();
  final _paymentMethod = TextEditingController();
  final _notes = TextEditingController();

  ExpenseCategory _category = ExpenseCategory.rent;
  ExpenseStatus _status = ExpenseStatus.paid;
  DateTime _date = DateTime.now();
  String _vendorId = '';
  String _vendorName = '';
  bool _isRecurring = false;

  bool get _isEditing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    if (expense != null) {
      _amount.text = expense.amount.toStringAsFixed(2);
      _tax.text = expense.taxAmount == 0
          ? ''
          : expense.taxAmount.toStringAsFixed(2);
      _reference.text = expense.reference;
      _customCategory.text = expense.customCategory;
      _paymentMethod.text = expense.paymentMethod;
      _notes.text = expense.notes;
      _category = expense.category;
      _status = expense.status;
      _date = expense.expenseDate;
      _vendorId = expense.vendorId;
      _vendorName = expense.vendorName;
      _isRecurring = expense.isRecurring;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _tax.dispose();
    _reference.dispose();
    _customCategory.dispose();
    _paymentMethod.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickVendor() async {
    final vendors = context.read<VendorProvider>().vendors;
    final selected = await showSearchablePicker(
      context: context,
      title: 'Who was paid?',
      selectedValue: _vendorId.isEmpty ? null : _vendorId,
      items: [
        for (final v in vendors)
          PickerItem(
            value: v.id,
            label: v.name,
            subtitle: v.phone,
            icon: Icons.store_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final vendor = context.read<VendorProvider>().vendors.firstWhere(
      (v) => v.id == selected,
    );
    setState(() {
      _vendorId = vendor.id;
      _vendorName = vendor.name;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      showErrorSnackBar(context, 'Enter the amount this cost.');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<ExpenseProvider>();
    final now = DateTime.now();
    final existing = widget.expense;

    final expense = ExpenseModel(
      id: existing?.id ?? '',
      reference: _reference.text.trim(),
      category: _category,
      customCategory: _category == ExpenseCategory.other
          ? _customCategory.text.trim()
          : '',
      vendorId: _vendorId,
      vendorName: _vendorName,
      amount: amount,
      taxAmount: double.tryParse(_tax.text.trim()) ?? 0,
      status: _status,
      paymentMethod: _paymentMethod.text.trim(),
      expenseDate: _date,
      paidAt: _status == ExpenseStatus.paid ? (existing?.paidAt ?? now) : null,
      notes: _notes.text.trim(),
      isRecurring: _isRecurring,
      createdBy: existing?.createdBy ?? user?.uid ?? '',
      createdByName: existing?.createdByName ?? user?.name ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final ok = _isEditing
        ? await provider.updateExpense(expense)
        : (await provider.addExpense(expense)) != null;

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        _isEditing ? 'Expense updated.' : 'Expense recorded.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  Future<void> _delete() async {
    final expense = widget.expense;
    if (expense == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this expense?',
      message: 'It disappears from the month totals and any budget built on '
          'them.',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<ExpenseProvider>();
    final ok = await provider.deleteExpense(expense.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Expense deleted.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Delete failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageExpenses,
      featureName: 'Expenses',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = context.watch<ExpenseProvider>().isBusy;
    final symbol = Money.symbolOf(context);

    return AppScreenScaffold(
      icon: Icons.account_balance_wallet_rounded,
      title: _isEditing ? 'Edit Expense' : 'Record Expense',
      iconColor: AppTheme.warningColor,
      actions: [
        if (_isEditing)
          IconButton(
            onPressed: busy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete',
          ),
      ],
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            FormSection(
              title: 'What it was for',
              icon: Icons.category_rounded,
              index: 0,
              children: [
                DropdownButtonFormField<ExpenseCategory>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Head'),
                  items: [
                    for (final category in ExpenseCategory.values)
                      DropdownMenuItem(
                        value: category,
                        child: Text(ExpenseModel.categoryLabelOf(category)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                if (_category == ExpenseCategory.other) ...[
                  const SizedBox(height: 12),
                  CustomTextField(
                    controller: _customCategory,
                    label: 'Name this head',
                    hint: 'Cleaning, subscriptions, licence fees…',
                    helperText:
                        'Kept as its own head so next month lands in the same '
                        'bucket.',
                  ),
                ],
                const SizedBox(height: 12),
                EntityPickerField(
                  label: 'Paid to (optional)',
                  icon: Icons.store_rounded,
                  value: _vendorName.isEmpty ? null : _vendorName,
                  onTap: _pickVendor,
                  onClear: _vendorId.isEmpty
                      ? null
                      : () => setState(() {
                          _vendorId = '';
                          _vendorName = '';
                        }),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _reference,
                  label: 'Bill or voucher number (optional)',
                ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'How much',
              icon: Icons.payments_rounded,
              index: 1,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _amount,
                        label: 'Amount',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        prefixIcon: Icons.currency_rupee_rounded,
                        validator: (value) {
                          final parsed = double.tryParse(value?.trim() ?? '');
                          if (parsed == null || parsed <= 0) {
                            return 'Enter an amount';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: _tax,
                        label: 'Tax (optional)',
                        helperText: 'Held apart from the cost',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_rounded,
                          size: 18,
                          color: AppTheme.textSec(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Dated ${_date.day}/${_date.month}/${_date.year}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          'Change',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SegmentedButton<ExpenseStatus>(
                  segments: const [
                    ButtonSegment(
                      value: ExpenseStatus.paid,
                      label: Text('Paid'),
                      icon: Icon(Icons.check_circle_rounded),
                    ),
                    ButtonSegment(
                      value: ExpenseStatus.unpaid,
                      label: Text('Unpaid'),
                      icon: Icon(Icons.schedule_rounded),
                    ),
                  ],
                  selected: {_status},
                  onSelectionChanged: (values) =>
                      setState(() => _status = values.first),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _paymentMethod,
                  label: 'Payment method (optional)',
                  hint: 'Bank transfer, cash, card…',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isRecurring,
                  onChanged: (value) => setState(() => _isRecurring = value),
                  title: const Text('This one repeats every period'),
                  subtitle: Text(
                    'A label only — nothing is generated automatically.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
                CustomTextField(
                  controller: _notes,
                  label: 'Notes',
                  maxLines: 2,
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : _save,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_isEditing ? 'Save changes' : 'Record expense'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Recorded spend flows into the Profit & Loss report as an '
              'operating cost, beneath the gross margin. Amounts are in '
              '$symbol.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppTheme.textSec(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
