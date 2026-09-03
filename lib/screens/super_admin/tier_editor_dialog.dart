import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/feature_map.dart';
import '../../config/theme.dart';
import '../../models/company_plan_model.dart';
import '../../providers/plan_catalog_provider.dart';
import '../../utils/responsive.dart';

/// Creates or edits one tier in the platform catalog.
///
/// The tiers used to be `const` in the Dart source, so a price change was a
/// redeploy. This writes `plans/{id}`, which every client hydrates
/// [PlanCatalog] from at boot.
Future<bool> showTierEditor(
  BuildContext context, {
  PlanDefinition? plan,
  required int workspacesOnPlan,
}) async {
  final catalog = context.read<PlanCatalogProvider>();
  final result = await showDialog<bool>(
    context: context,
    // The dialog is a separate subtree, so the provider is handed down
    // explicitly rather than looked up under a route that does not carry it.
    builder: (_) => ChangeNotifierProvider<PlanCatalogProvider>.value(
      value: catalog,
      child: _TierEditorDialog(
        plan: plan,
        workspacesOnPlan: workspacesOnPlan,
      ),
    ),
  );
  return result ?? false;
}

class _TierEditorDialog extends StatefulWidget {
  const _TierEditorDialog({
    required this.plan,
    required this.workspacesOnPlan,
  });

  /// Null when creating a new tier.
  final PlanDefinition? plan;
  final int workspacesOnPlan;

  @override
  State<_TierEditorDialog> createState() => _TierEditorDialogState();
}

class _TierEditorDialogState extends State<_TierEditorDialog> {
  late final bool _isNew = widget.plan == null;

  late final TextEditingController _id = TextEditingController(
    text: widget.plan?.id ?? '',
  );
  late final TextEditingController _label = TextEditingController(
    text: widget.plan?.label ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.plan?.description ?? '',
  );
  late final TextEditingController _nominal = TextEditingController(
    text: widget.plan?.nominalPrice?.toString() ?? '',
  );
  late final TextEditingController _promotional = TextEditingController(
    text: widget.plan?.promotionalPrice?.toString() ?? '',
  );
  late final TextEditingController _sortOrder = TextEditingController(
    text: (widget.plan?.sortOrder ?? 0).toString(),
  );
  late final Map<String, TextEditingController> _limits = {
    for (final key in PlanLimitKeys.all)
      key: TextEditingController(
        text: widget.plan?.limits[key]?.toString() ?? '',
      ),
  };
  late final Set<String> _locked = {...?widget.plan?.lockedFeatures};
  late bool _archived = widget.plan?.archived ?? false;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _label.dispose();
    _description.dispose();
    _nominal.dispose();
    _promotional.dispose();
    _sortOrder.dispose();
    for (final c in _limits.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _resolvedId {
    if (!_isNew) return widget.plan!.id;
    // Slugified so a tier id is always a safe document id and a stable key for
    // the `plan.planId` already stored on company documents.
    return _id.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Future<void> _save() async {
    final id = _resolvedId;
    if (id.isEmpty) {
      setState(() => _error = 'A tier needs an id.');
      return;
    }
    if (_label.text.trim().isEmpty) {
      setState(() => _error = 'A tier needs a name.');
      return;
    }
    // MAX is the fallback for every company doc with no plan field, so it must
    // always exist and always remain assignable.
    if (id == PlanCatalog.defaultId && _archived) {
      setState(
        () => _error =
            'The default tier cannot be archived — every workspace with no '
            'plan of its own falls back to it.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final limits = <String, int>{};
    _limits.forEach((key, controller) {
      final value = int.tryParse(controller.text.trim());
      // Blank means "no cap on this key" — not zero, which would cap it at
      // nothing and refuse the tenant's very next write.
      if (value != null && value >= 0) limits[key] = value;
    });

    final plan = PlanDefinition(
      id: id,
      label: _label.text.trim(),
      description: _description.text.trim(),
      nominalPrice: int.tryParse(_nominal.text.trim()),
      promotionalPrice: int.tryParse(_promotional.text.trim()),
      limits: limits,
      lockedFeatures: _locked,
      sortOrder: int.tryParse(_sortOrder.text.trim()) ?? 0,
      archived: _archived,
    );

    final ok = await context.read<PlanCatalogProvider>().savePlan(plan);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = 'Could not save the tier. Check your connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = Responsive.isMobile(context);

    return AlertDialog(
      scrollable: true,
      title: Text(_isNew ? 'New tier' : 'Edit ${widget.plan!.label}'),
      content: SizedBox(
        width: Responsive.dialogMaxWidth(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isNew && widget.workspacesOnPlan > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${widget.workspacesOnPlan} workspace'
                  '${widget.workspacesOnPlan == 1 ? '' : 's'} '
                  'are on this tier. Changes to its limits apply to them '
                  'immediately.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.warningColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_isNew)
              TextField(
                controller: _id,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Tier id',
                  helperText:
                      'Stored on every company on this tier. It cannot be '
                      'changed later.',
                  isDense: true,
                ),
              )
            else
              Text(
                'Tier id: ${widget.plan!.id}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.textSec(context)),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              enabled: !_saving,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nominal,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'List price',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _promotional,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Promo price',
                      helperText: '0 = free',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Text(
              'Limits',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              'Blank means this tier does not cap it.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSec(context)),
            ),
            const SizedBox(height: 8),
            for (final key in PlanLimitKeys.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            PlanLimitKeys.labelOf(key),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          _limitField(key),
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
                          SizedBox(width: 110, child: _limitField(key)),
                        ],
                      ),
              ),
            const Divider(height: 28),
            Text(
              'Features this tier does NOT include',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            // Driven by FeatureMap so the picker cannot drift from what the app
            // actually offers.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in FeatureMap.all)
                  FilterChip(
                    label: Text(entry.label, overflow: TextOverflow.ellipsis),
                    selected: _locked.contains(entry.id),
                    showCheckmark: false,
                    selectedColor: AppTheme.dangerColor.withValues(alpha: 0.16),
                    onSelected: _saving
                        ? null
                        : (on) => setState(() {
                            on ? _locked.add(entry.id) : _locked.remove(entry.id);
                          }),
                  ),
              ],
            ),
            const Divider(height: 28),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sortOrder,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Sort order',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _archived,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _archived = v),
              title: const Text('Archived'),
              subtitle: const Text(
                'Hidden from new assignments. Workspaces already on it keep it.',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.dangerColor,
                ),
              ),
            ],
          ],
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
              : Text(_isNew ? 'Create tier' : 'Save'),
        ),
      ],
    );
  }

  Widget _limitField(String key) => TextField(
    controller: _limits[key],
    enabled: !_saving,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: const InputDecoration(isDense: true, hintText: 'no cap'),
  );
}
