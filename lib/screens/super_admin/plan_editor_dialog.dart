import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/company_model.dart';
import '../../models/company_plan_model.dart';
import '../../providers/plan_catalog_provider.dart';
import '../../providers/super_admin_provider.dart';
import '../../utils/currency.dart';
import '../../utils/date_formats.dart';
import '../../utils/responsive.dart';

/// Platform prices are the platform's own — not the tenant's configured
/// currency. See the note in plans_section.dart.
String _platformPrice(num value) =>
    Money.withSymbol(AppTheme.currencySymbol, value, decimals: 0);

/// Assigns a tier, subscription status, trial end, and per-company limit
/// overrides to one workspace.
///
/// Replaces the single inert radio the console shipped with when the catalog
/// held one plan.
Future<bool> showPlanEditor(BuildContext context, CompanyModel company) async {
  final superAdmin = context.read<SuperAdminProvider>();
  final catalog = context.read<PlanCatalogProvider>();
  final result = await showDialog<bool>(
    context: context,
    // A dialog is its own subtree; both providers are passed down so the tier
    // list here is the live catalog rather than the compiled seed.
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SuperAdminProvider>.value(value: superAdmin),
        ChangeNotifierProvider<PlanCatalogProvider>.value(value: catalog),
      ],
      child: _PlanEditorDialog(company: company),
    ),
  );
  return result ?? false;
}

class _PlanEditorDialog extends StatefulWidget {
  const _PlanEditorDialog({required this.company});

  final CompanyModel company;

  @override
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
  late String _planId = widget.company.plan.planId;
  late PlanStatus _status = widget.company.plan.status;
  late DateTime? _trialEndsAt = widget.company.plan.trialEndsAt;
  late final TextEditingController _note = TextEditingController(
    text: widget.company.plan.note,
  );
  late final Map<String, TextEditingController> _overrides = {
    for (final key in PlanLimitKeys.all)
      key: TextEditingController(
        text: widget.company.plan.limitOverrides[key]?.toString() ?? '',
      ),
  };
  bool _saving = false;

  /// Rendered inside the dialog. A snackbar here appears *behind* the modal
  /// barrier, so the one message the admin needs is the one they cannot read.
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    for (final c in _overrides.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, int> _collectOverrides() {
    final out = <String, int>{};
    _overrides.forEach((key, controller) {
      final text = controller.text.trim();
      if (text.isEmpty) return;
      final value = int.tryParse(text);
      // A blank field means "no override"; an unparseable one is dropped
      // rather than silently written as 0, which would cap the workspace at
      // nothing.
      if (value != null) out[key] = value;
    });
    return out;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final provider = context.read<SuperAdminProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await provider.setPlan(
      companyId: widget.company.id,
      planId: _planId,
      status: _status,
      trialEndsAt: _trialEndsAt,
      limitOverrides: _collectOverrides(),
      note: _note.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, true);
      // Captured before the pop: the success message belongs to the screen
      // underneath, not to this dialog's disposed context.
      messenger.showSnackBar(const SnackBar(content: Text('Plan updated')));
    } else {
      setState(
        () => _error = provider.errorMessage ?? 'Could not change the plan.',
      );
    }
  }

  Widget _limitField(String key, PlanDefinition selected) => TextField(
    controller: _overrides[key],
    enabled: !_saving,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
    decoration: InputDecoration(
      isDense: true,
      hintText: selected.limitFor(key)?.toString() ?? 'none',
    ),
  );

  @override
  Widget build(BuildContext context) {
    final selected = PlanCatalog.byId(_planId);
    final narrow = Responsive.isMobile(context);
    // Only assignable tiers are offered, but an archived tier the workspace is
    // already on stays in the list — otherwise the radio group would have no
    // selected option and the current plan would look wrong.
    final catalog = context.watch<PlanCatalogProvider>();
    final offered = [
      ...catalog.assignable,
      if (!catalog.assignable.any((p) => p.id == _planId) &&
          catalog.plans.any((p) => p.id == _planId))
        catalog.plans.firstWhere((p) => p.id == _planId),
    ];

    return AlertDialog(
      title: Text('Plan — ${widget.company.displayName}'),
      content: SizedBox(
        // The dialog is clamped to the screen anyway; a hardcoded 460 just meant
        // the inner rows were laid out for a width mobile never gets.
        width: Responsive.dialogMaxWidth(context),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final plan in offered)
                RadioListTile<String>(
                  value: plan.id,
                  groupValue: _planId,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _planId = v ?? _planId),
                  contentPadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          plan.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (plan.nominalPrice != null)
                        Text(
                          plan.promotionalPrice == 0
                              ? '${_platformPrice(plan.nominalPrice!)} · free now'
                              : _platformPrice(plan.nominalPrice!),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  subtitle: Text(
                    plan.limits.isEmpty
                        ? '${plan.description}\nNo limits.'
                        : '${plan.description}\n'
                              '${plan.limits.entries.map((e) => '${PlanLimitKeys.labelOf(e.key)} ${e.value}').join(' · ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  isThreeLine: true,
                ),
              const Divider(height: 24),
              DropdownButtonFormField<PlanStatus>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Subscription status',
                  isDense: true,
                ),
                items: [
                  for (final s in PlanStatus.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text(CompanyPlan.statusLabel(s)),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _trialEndsAt == null
                          ? 'No trial end set'
                          : 'Trial ends ${AppDates.day.format(_trialEndsAt!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            final now = DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _trialEndsAt ?? now,
                              firstDate: now.subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: now.add(const Duration(days: 3650)),
                            );
                            if (picked != null) {
                              setState(() => _trialEndsAt = picked);
                            }
                          },
                    child: const Text('Set'),
                  ),
                  if (_trialEndsAt != null)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _trialEndsAt = null),
                      child: const Text('Clear'),
                    ),
                ],
              ),
              const Divider(height: 24),
              Text(
                'Limit overrides',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                'Blank keeps the tier value. Use -1 to remove the cap for this '
                'workspace only.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSec(context),
                ),
              ),
              const SizedBox(height: 8),
              for (final key in PlanLimitKeys.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  // Stacked on mobile: side by side, the fixed field left about
                  // 120px for the label inside a ~280px dialog.
                  child: narrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              PlanLimitKeys.labelOf(key),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            _limitField(key, selected),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Text(
                                PlanLimitKeys.labelOf(key),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            SizedBox(width: 110, child: _limitField(key, selected)),
                          ],
                        ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Note (why this changed)',
                  isDense: true,
                ),
                maxLines: 2,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: AppTheme.dangerColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.dangerColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save plan'),
        ),
      ],
    );
  }
}
