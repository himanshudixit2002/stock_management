import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/budget_model.dart';
import '../../models/expense_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/budget_provider.dart';
import '../../utils/currency.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/form_section.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/searchable_picker.dart';

/// Writes or edits a period budget.
class BudgetEditorScreen extends StatefulWidget {
  const BudgetEditorScreen({super.key, this.budget});

  final BudgetModel? budget;

  @override
  State<BudgetEditorScreen> createState() => _BudgetEditorScreenState();
}

class _BudgetEditorScreenState extends State<BudgetEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _notes = TextEditingController();

  BudgetPeriod _period = BudgetPeriod.month;
  late DateTime _periodStart = BudgetModel.normalizeStart(
    DateTime.now(),
    BudgetPeriod.month,
  );
  List<BudgetLine> _lines = [];
  bool _isActive = true;

  bool get _isEditing => widget.budget != null;

  @override
  void initState() {
    super.initState();
    final budget = widget.budget;
    if (budget != null) {
      _name.text = budget.name;
      _notes.text = budget.notes;
      _period = budget.period;
      _periodStart = budget.periodStart;
      _lines = [...budget.lines];
      _isActive = budget.isActive;
    } else {
      // A budget with nothing in it measures nothing, so the two lines every
      // workspace has are there from the start.
      _lines = const [
        BudgetLine(type: BudgetLineType.revenue, label: 'Revenue'),
        BudgetLine(type: BudgetLineType.purchases, label: 'Purchases'),
      ];
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPeriodStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _periodStart,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 3),
      helpText: 'Any day inside the period',
    );
    if (picked != null && mounted) {
      setState(() {
        _periodStart = BudgetModel.normalizeStart(picked, _period);
      });
    }
  }

  Future<void> _addExpenseLine() async {
    final selected = await showSearchablePicker(
      context: context,
      title: 'Which expense head?',
      items: [
        const PickerItem(
          value: '',
          label: 'All operating expenses',
          subtitle: 'One line covering every head',
          icon: Icons.all_inclusive_rounded,
        ),
        for (final category in ExpenseCategory.values)
          PickerItem(
            value: ExpenseModel.categoryToString(category),
            label: ExpenseModel.categoryLabelOf(category),
            icon: Icons.receipt_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    final key = 'expense:$selected';
    if (_lines.any((l) => l.key == key)) {
      showInfoSnackBar(context, 'That head is already budgeted.');
      return;
    }
    setState(() {
      _lines = [
        ..._lines,
        BudgetLine(
          type: BudgetLineType.expense,
          categoryKey: selected,
          label: selected.isEmpty
              ? 'Operating expenses'
              : ExpenseModel.categoryLabelOf(
                  ExpenseModel.categoryFromString(selected),
                ),
        ),
      ];
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final lines = _lines.where((l) => l.amount > 0).toList();
    if (lines.isEmpty) {
      showErrorSnackBar(context, 'Give at least one line an amount.');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<BudgetProvider>();
    final now = DateTime.now();
    final existing = widget.budget;

    final budget = BudgetModel(
      id: existing?.id ?? '',
      name: _name.text.trim(),
      period: _period,
      periodStart: BudgetModel.normalizeStart(_periodStart, _period),
      lines: lines,
      isActive: _isActive,
      notes: _notes.text.trim(),
      createdBy: existing?.createdBy ?? user?.uid ?? '',
      createdByName: existing?.createdByName ?? user?.name ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final ok = _isEditing
        ? await provider.updateBudget(budget)
        : (await provider.addBudget(budget)) != null;

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        _isEditing ? 'Budget updated.' : 'Budget set.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  Future<void> _delete() async {
    final budget = widget.budget;
    if (budget == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this budget?',
      message: 'Nothing else changes — the actuals it measured stay where they '
          'are.',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<BudgetProvider>();
    final ok = await provider.deleteBudget(budget.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Budget deleted.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Delete failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageBudgets,
      featureName: 'Budgets',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = context.watch<BudgetProvider>().isBusy;
    final symbol = Money.symbolOf(context);
    final preview = BudgetModel(
      id: '',
      name: '',
      period: _period,
      periodStart: BudgetModel.normalizeStart(_periodStart, _period),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    return AppScreenScaffold(
      icon: Icons.donut_small_rounded,
      title: _isEditing ? 'Edit Budget' : 'New Budget',
      iconColor: AppTheme.successColor,
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
              title: 'The period',
              icon: Icons.event_rounded,
              index: 0,
              children: [
                CustomTextField(
                  controller: _name,
                  label: 'Name',
                  hint: 'Q3 operating budget, September plan…',
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Give the budget a name'
                      : null,
                ),
                const SizedBox(height: 12),
                SegmentedButton<BudgetPeriod>(
                  segments: const [
                    ButtonSegment(
                      value: BudgetPeriod.month,
                      label: Text('Month'),
                    ),
                    ButtonSegment(
                      value: BudgetPeriod.quarter,
                      label: Text('Quarter'),
                    ),
                    ButtonSegment(
                      value: BudgetPeriod.year,
                      label: Text('Year'),
                    ),
                  ],
                  selected: {_period},
                  onSelectionChanged: (values) => setState(() {
                    _period = values.first;
                    _periodStart = BudgetModel.normalizeStart(
                      _periodStart,
                      _period,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickPeriodStart,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.date_range_rounded,
                          size: 18,
                          color: AppTheme.textSec(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Covers ${preview.periodLabel}',
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
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Active'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Lines',
              subtitle: 'Each one is measured against real data',
              icon: Icons.list_alt_rounded,
              index: 1,
              trailing: TextButton.icon(
                onPressed: _addExpenseLine,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Expense head'),
              ),
              children: [
                for (var i = 0; i < _lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassPanel(
                      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _lines[i].displayLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  BudgetLine.typeLabelOf(_lines[i].type),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSec(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: TextFormField(
                              initialValue: _lines[i].amount == 0
                                  ? ''
                                  : _lines[i].amount.toStringAsFixed(0),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              textAlign: TextAlign.end,
                              decoration: InputDecoration(
                                labelText: 'Amount',
                                isDense: true,
                                prefixText: symbol,
                              ),
                              onChanged: (value) {
                                final next = [..._lines];
                                next[i] = next[i].copyWith(
                                  amount: double.tryParse(value) ?? 0,
                                );
                                _lines = next;
                              },
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              final next = [..._lines]..removeAt(i);
                              _lines = next;
                            }),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Revenue is measured from sales invoices net of tax, '
                  'purchases from the orders raised in the period, and each '
                  'expense head from the expenses recorded against it.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSec(context),
                  ),
                ),
                const SizedBox(height: 12),
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
                label: Text(_isEditing ? 'Save changes' : 'Set budget'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
