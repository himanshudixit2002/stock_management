import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/commission_plan_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/commission_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/auth_service.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/form_section.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/searchable_picker.dart';

/// Writes or edits a commission scheme.
class CommissionPlanEditorScreen extends StatefulWidget {
  const CommissionPlanEditorScreen({super.key, this.plan});

  final CommissionPlanModel? plan;

  @override
  State<CommissionPlanEditorScreen> createState() =>
      _CommissionPlanEditorScreenState();
}

class _CommissionPlanEditorScreenState
    extends State<CommissionPlanEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _percent = TextEditingController();
  final _minimum = TextEditingController();
  final _notes = TextEditingController();

  CommissionBasis _basis = CommissionBasis.revenue;
  bool _includeUnpaid = false;
  bool _isActive = true;
  List<String> _userIds = [];
  List<CommissionRate> _rates = [];

  bool get _isEditing => widget.plan != null;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    if (plan != null) {
      _name.text = plan.name;
      _percent.text = plan.defaultPercent.toString();
      _minimum.text = plan.minimumSaleValue == 0
          ? ''
          : plan.minimumSaleValue.toStringAsFixed(0);
      _notes.text = plan.notes;
      _basis = plan.basis;
      _includeUnpaid = plan.includeUnpaid;
      _isActive = plan.isActive;
      _userIds = [...plan.userIds];
      _rates = [...plan.categoryRates];
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _percent.dispose();
    _minimum.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addCategoryRate() async {
    final categories = context.read<CategoryProvider>().categories;
    final selected = await showSearchablePicker(
      context: context,
      title: 'Which category?',
      items: [
        for (final category in categories)
          if (!_rates.any((r) => r.categoryId == category.id))
            PickerItem(
              value: category.id,
              label: category.name,
              icon: Icons.category_rounded,
            ),
      ],
    );
    if (selected == null || !mounted) return;
    final category = categories.firstWhere((c) => c.id == selected);
    setState(() {
      _rates = [
        ..._rates,
        CommissionRate(
          categoryId: category.id,
          categoryName: category.name,
          percent: double.tryParse(_percent.text.trim()) ?? 0,
        ),
      ];
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final percent = double.tryParse(_percent.text.trim()) ?? 0;
    if (percent <= 0 && _rates.isEmpty) {
      showErrorSnackBar(context, 'Set a rate, or add a category rate.');
      return;
    }

    final user = context.read<AuthProvider>().currentUser;
    final provider = context.read<CommissionProvider>();
    final now = DateTime.now();
    final existing = widget.plan;

    final plan = CommissionPlanModel(
      id: existing?.id ?? '',
      name: _name.text.trim(),
      basis: _basis,
      defaultPercent: percent,
      categoryRates: _rates,
      userIds: _userIds,
      includeUnpaid: _includeUnpaid,
      minimumSaleValue: double.tryParse(_minimum.text.trim()) ?? 0,
      isActive: _isActive,
      effectiveFrom: existing?.effectiveFrom,
      effectiveTo: existing?.effectiveTo,
      notes: _notes.text.trim(),
      createdBy: existing?.createdBy ?? user?.uid ?? '',
      createdByName: existing?.createdByName ?? user?.name ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final ok = _isEditing
        ? await provider.updatePlan(plan)
        : (await provider.addPlan(plan)) != null;

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(
        context,
        _isEditing ? 'Plan updated.' : 'Commission plan created.',
      );
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Save failed.');
    }
  }

  Future<void> _delete() async {
    final plan = widget.plan;
    if (plan == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this plan?',
      message:
          'Statements for past periods are computed from the plans that exist '
          'now, so deleting one changes what those periods report. Marking it '
          'inactive keeps the history intact.',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<CommissionProvider>();
    final ok = await provider.deletePlan(plan.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      showSuccessSnackBar(context, 'Plan deleted.');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Delete failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageCommissions,
      featureName: 'Commission Plans',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final busy = context.watch<CommissionProvider>().isBusy;
    final companyId = context.watch<SettingsProvider>().companyId;

    return AppScreenScaffold(
      icon: Icons.percent_rounded,
      title: _isEditing ? 'Edit Plan' : 'New Commission Plan',
      iconColor: AppTheme.violetColor,
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
              title: 'The scheme',
              icon: Icons.percent_rounded,
              index: 0,
              children: [
                CustomTextField(
                  controller: _name,
                  label: 'Plan name',
                  hint: 'House scheme, Field sales, Q4 push…',
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Give the plan a name'
                      : null,
                ),
                const SizedBox(height: 12),
                SegmentedButton<CommissionBasis>(
                  segments: const [
                    ButtonSegment(
                      value: CommissionBasis.revenue,
                      label: Text('Revenue'),
                    ),
                    ButtonSegment(
                      value: CommissionBasis.margin,
                      label: Text('Margin'),
                    ),
                  ],
                  selected: {_basis},
                  onSelectionChanged: (values) =>
                      setState(() => _basis = values.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _basis == CommissionBasis.revenue
                      ? 'A percentage of what was sold, net of discounts and '
                            'excluding tax.'
                      : 'A percentage of the profit — sale price less the '
                            'product cost price. A heavily discounted sale '
                            'earns less, which is usually the point.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSec(context),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _percent,
                        label: 'Rate %',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: _minimum,
                        label: 'Minimum sale',
                        helperText: 'Optional floor',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includeUnpaid,
                  onChanged: (value) => setState(() => _includeUnpaid = value),
                  title: const Text('Pay on issue, not on collection'),
                  subtitle: Text(
                    _includeUnpaid
                        ? 'Commission is earned the moment the invoice is '
                              'raised, paid or not.'
                        : 'Only the collected share of an invoice earns '
                              'commission — a part-paid invoice earns part.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSec(context),
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
              title: 'Category rates',
              subtitle: 'Override the plan rate for particular categories',
              icon: Icons.category_rounded,
              index: 1,
              trailing: TextButton.icon(
                onPressed: _addCategoryRate,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
              ),
              children: [
                if (_rates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Every category earns the plan rate.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < _rates.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassPanel(
                        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _rates[i].categoryName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                initialValue: _rates[i].percent.toString(),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  labelText: '%',
                                  isDense: true,
                                ),
                                onChanged: (value) {
                                  final next = [..._rates];
                                  next[i] = next[i].copyWith(
                                    percent: double.tryParse(value) ?? 0,
                                  );
                                  _rates = next;
                                },
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() {
                                final next = [..._rates]..removeAt(i);
                                _rates = next;
                              }),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            FormSection(
              title: 'Who it applies to',
              subtitle: 'Nobody selected means everybody',
              icon: Icons.people_rounded,
              index: 2,
              children: [
                StreamBuilder<List<UserModel>>(
                  stream: companyId.isEmpty
                      ? const Stream.empty()
                      : AuthService().getAllUsers(companyId: companyId),
                  builder: (context, snapshot) {
                    final users = snapshot.data ?? const <UserModel>[];
                    if (users.isEmpty) {
                      return Text(
                        'No team members to choose from yet.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.textSec(context),
                        ),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final user in users)
                          FilterChip(
                            label: Text(
                              user.name.isEmpty ? user.email : user.name,
                            ),
                            selected: _userIds.contains(user.uid),
                            onSelected: (selected) => setState(() {
                              _userIds = selected
                                  ? [..._userIds, user.uid]
                                  : (_userIds..remove(user.uid)).toList();
                            }),
                          ),
                      ],
                    );
                  },
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
                label: Text(_isEditing ? 'Save changes' : 'Create plan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
