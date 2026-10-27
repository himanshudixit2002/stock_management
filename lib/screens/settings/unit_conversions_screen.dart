import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../models/unit_conversion_rule.dart';
import '../../providers/audit_log_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/unit_conversion_planner.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../utils/unit_conversion.dart';
import '../../widgets/app_screen_scaffold.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/permission_gate.dart';
import '../../widgets/searchable_picker.dart';
import 'settings_context.dart';
import 'settings_page_shell.dart';
import 'unit_conversion_review_sheet.dart';

/// Settings › Unit conversions: "1 box = 10 pcs", said once for a category, a
/// brand or a sub-category instead of on every product.
///
/// Saving a rule changes no product by itself. It opens the review, which says
/// exactly what will change — and what has to wait — before anything is
/// written, and the same review is one tap away whenever products have
/// drifted from their rules (an import, the assistant, a cancelled review).
class UnitConversionsScreen extends StatefulWidget {
  const UnitConversionsScreen({super.key});

  @override
  State<UnitConversionsScreen> createState() => _UnitConversionsScreenState();
}

class _UnitConversionsScreenState extends State<UnitConversionsScreen> {
  List<ProductModel>? _catalog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Fresh rules and a fresh catalog. A stock conversion refuses to run on a
  /// product that has moved since it was reviewed, so planning from a cached
  /// catalog would only produce refusals.
  Future<void> _load() async {
    final settings = context.read<SettingsProvider>();
    final products = context.read<ProductProvider>();
    await Future.wait([
      settings.reloadUnitSettings(),
      products.loadAnalytics(force: true),
    ]);
    if (!mounted) return;
    setState(() => _catalog = products.analyticsProducts);
  }

  Future<void> _review() async {
    final catalog = _catalog;
    if (catalog == null) return;
    final wrote = await showUnitConversionReview(context, catalog: catalog);
    if (wrote == true && mounted) {
      setState(() => _catalog = null);
      await _load();
    }
  }

  void _logRuleChange(String action, UnitConversionRule rule, String scope) {
    final user = context.read<AuthProvider>().currentUser;
    unawaited(
      context.read<AuditLogProvider>().logAction(
        action: action,
        entityType: 'Settings',
        entityId: rule.id,
        entityName: 'Unit conversion',
        userId: user?.uid ?? '',
        userName: user?.name ?? '',
        changes: {'scope': scope, 'conversion': rule.label},
      ),
    );
  }

  Future<void> _editRule(UnitConversionRule? rule) async {
    final catalog = _catalog;
    if (catalog == null) return;
    final saved = await showModalBottomSheet<UnitConversionRule>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RuleSheet(rule: rule, catalog: catalog),
    );
    if (saved == null || !mounted) return;
    _logRuleChange(
      rule == null ? 'unit_conversion_added' : 'unit_conversion_changed',
      saved,
      _scopeLabel(saved, context.read<CategoryProvider>().categories),
    );
    await _review();
  }

  Future<void> _deleteRule(UnitConversionRule rule, String scope) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this conversion?',
      message:
          'Products it covers ($scope) keep ${rule.label} unless another '
          'conversion covers them. No stock changes.',
    );
    if (!confirmed || !mounted) return;
    final settings = context.read<SettingsProvider>();
    if (!await settings.deleteUnitConversion(rule.id)) {
      if (mounted) {
        showErrorSnackBar(
          context,
          settings.errorMessage ?? 'Could not delete the conversion',
        );
      }
      return;
    }
    if (!mounted) return;
    _logRuleChange('unit_conversion_deleted', rule, scope);
    // Products it covered may now fall to a broader conversion.
    final catalog = _catalog;
    if (catalog != null &&
        planUnitChanges(
          catalog,
          settings.unitConversions,
        ).any((c) => c.writes)) {
      await _review();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.manageCompanySettings,
      featureName: 'Unit conversions',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final categories = context.watch<CategoryProvider>().categories;
    final readOnly = isInspectingWorkspace(context);
    final catalog = _catalog;
    final rules = [...settings.unitConversions]..sort(_mostSpecificFirst);

    final covers = <String, int>{};
    var pending = 0;
    if (catalog != null) {
      for (final product in catalog) {
        final rule = resolveUnitConversionFor(rules, product);
        if (rule == null) continue;
        covers[rule.id] = (covers[rule.id] ?? 0) + 1;
        if (planUnitChange(product, rule).writes) pending++;
      }
    }

    return AppScreenScaffold(
      icon: Icons.autorenew_rounded,
      title: 'Unit conversions',
      subtitle: 'Say "1 box = 10 pcs" once',
      iconColor: AppTheme.violetColor,
      isLoading: catalog == null,
      isEmpty: rules.isEmpty,
      emptyState: EmptyStateWidget(
        icon: Icons.autorenew_rounded,
        title: 'No conversions yet',
        subtitle:
            'Say once that a box of tiles holds 10 pieces, and every product '
            'in that category, brand or sub-category follows it — wherever '
            'stock is counted, bought or sold.',
        buttonText: readOnly ? null : 'Add a conversion',
        onButtonPressed: readOnly ? null : () => _editRule(null),
      ),
      floatingActionButton: readOnly || rules.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editRule(null),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add conversion'),
            ),
      body: SettingsPageBody(
        children: [
          if (readOnly)
            const SettingsNote(
              text: kInspectionReadOnlyNote,
              icon: Icons.visibility_rounded,
              color: AppTheme.warningColor,
            ),
          if (pending > 0)
            _PendingBanner(count: pending, onReview: readOnly ? null : _review),
          SettingsGroup(
            title: 'Conversions',
            subtitle:
                'Where two cover a product, the more specific one wins. '
                'Between equally specific ones, sub-category beats brand, and '
                'brand beats category.',
            children: [
              for (final (index, rule) in rules.indexed)
                _RuleCard(
                  index: index,
                  rule: rule,
                  scope: _scopeLabel(rule, categories),
                  categoryMissing:
                      rule.categoryId.isNotEmpty &&
                      !categories.any((c) => c.id == rule.categoryId),
                  covers: covers[rule.id] ?? 0,
                  onEdit: readOnly ? null : () => _editRule(rule),
                  onDelete: readOnly
                      ? null
                      : () => _deleteRule(rule, _scopeLabel(rule, categories)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

int _mostSpecificFirst(UnitConversionRule a, UnitConversionRule b) {
  final bySpecificity = b.specificity.compareTo(a.specificity);
  if (bySpecificity != 0) return bySpecificity;
  return b.precedence.compareTo(a.precedence);
}

/// "Tiles · Kajaria · 600x600", or "All products" for a rule with no scope.
String _scopeLabel(UnitConversionRule rule, List<CategoryModel> categories) {
  if (rule.coversEverything) return 'All products';
  final category = rule.categoryId.isEmpty
      ? null
      : categories.where((c) => c.id == rule.categoryId).firstOrNull?.name ??
            'Deleted category';
  return [
    ?category,
    if (rule.company.trim().isNotEmpty) rule.company.trim(),
    if (rule.size.trim().isNotEmpty) rule.size.trim(),
  ].join(' · ');
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count, required this.onReview});

  final int count;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.warningColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingMD),
        decoration: BoxDecoration(
          color: AppTheme.tint(context, accent),
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(Icons.pending_actions_rounded, color: accent),
            const SizedBox(width: AppTheme.spacingSM),
            Expanded(
              child: Text(
                count == 1
                    ? '1 product doesn\'t follow these conversions yet'
                    : '$count products don\'t follow these conversions yet',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPri(context),
                ),
              ),
            ),
            if (onReview != null)
              TextButton(onPressed: onReview, child: const Text('Review')),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.index,
    required this.rule,
    required this.scope,
    required this.categoryMissing,
    required this.covers,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final UnitConversionRule rule;
  final String scope;
  final bool categoryMissing;
  final int covers;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final detail = categoryMissing
        ? 'Category deleted · matches nothing'
        : covers == 1
        ? 'Covers 1 product'
        : 'Covers $covers products';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
      child: GlassCard(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.violetColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.autorenew_rounded,
                  color: AppTheme.violetColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPri(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scope,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSec(context),
                      ),
                    ),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12,
                        color: categoryMissing
                            ? AppTheme.warningColor
                            : AppTheme.textTer(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null || onDelete != null)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (value) =>
                      value == 'delete' ? onDelete?.call() : onEdit?.call(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Adds or edits one rule. Pops with the saved rule.
class _RuleSheet extends StatefulWidget {
  const _RuleSheet({required this.rule, required this.catalog});

  final UnitConversionRule? rule;
  final List<ProductModel> catalog;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  static const _newUnit = '__new_unit__';

  late final String _id;
  late String _categoryId;
  late String _company;
  late String _size;
  late String _packUnit;
  late String _baseUnit;
  late final TextEditingController _countController;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _id = rule?.id ?? 'uc${DateTime.now().microsecondsSinceEpoch}';
    _categoryId = rule?.categoryId ?? '';
    _company = rule?.company ?? '';
    _size = rule?.size ?? '';
    _packUnit = rule?.packUnit ?? 'box';
    _baseUnit = rule?.baseUnit ?? 'pcs';
    _countController = TextEditingController(
      text: rule == null ? '' : '${rule.unitsPerPack}',
    );
    _countController.addListener(() => setState(() => _saveError = null));
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  UnitConversionRule get _draft => UnitConversionRule(
    id: _id,
    categoryId: _categoryId,
    company: _company,
    size: _size,
    packUnit: _packUnit,
    unitsPerPack: int.tryParse(_countController.text.trim()) ?? 0,
    baseUnit: _baseUnit,
  );

  String? _problem(UnitConversionRule draft, List<UnitConversionRule> rules) {
    if (_countController.text.trim().isEmpty) return null;
    if (draft.validationError case final error?) return error;
    if (rules.any((r) => r.id != draft.id && r.sameScopeAs(draft))) {
      return 'Another conversion already covers exactly these products';
    }
    return null;
  }

  /// What saving would do: how many products this rule would cover, and how
  /// many of those need a pack change or a stock conversion to follow it.
  ({int covers, int repack, int convert}) _preview(
    UnitConversionRule draft,
    List<UnitConversionRule> rules,
  ) {
    final withDraft = [
      for (final rule in rules)
        if (rule.id != draft.id) rule,
      draft,
    ];
    var covers = 0, repack = 0, convert = 0;
    for (final product in widget.catalog) {
      final rule = resolveUnitConversionFor(withDraft, product);
      if (rule?.id != draft.id) continue;
      covers++;
      switch (planUnitChange(product, rule).kind) {
        case UnitChangeKind.repack:
          repack++;
        case UnitChangeKind.convertStock:
          convert++;
        case UnitChangeKind.none ||
            UnitChangeKind.keptCustom ||
            UnitChangeKind.unitMismatch:
          break;
      }
    }
    return (covers: covers, repack: repack, convert: convert);
  }

  Future<void> _pick({
    required String title,
    required List<PickerItem> items,
    required String selected,
    required ValueChanged<String> onPicked,
    bool canAddUnit = false,
  }) async {
    final settings = context.read<SettingsProvider>();
    final result = await showSearchablePicker(
      context: context,
      title: title,
      selectedValue: selected,
      items: items,
      addNewLabel: canAddUnit ? 'Add a unit' : null,
      addNewValue: canAddUnit ? _newUnit : null,
    );
    if (result == null || !mounted) return;
    if (result != _newUnit) {
      setState(() => onPicked(result));
      return;
    }
    final added = await showAddNameDialog(
      context,
      title: 'Add a unit',
      labelText: 'Unit name',
      hint: 'e.g. carton, strip, roll',
      onAdd: settings.addUnit,
    );
    if (added != null && mounted) setState(() => onPicked(added));
  }

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    final user = context.read<AuthProvider>().currentUser;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final draft = _draft;
    final ok = await settings.saveUnitConversion(
      draft,
      userId: user?.uid ?? '',
      userName: user?.name ?? '',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, draft);
      return;
    }
    setState(() {
      _saving = false;
      _saveError = settings.errorMessage ?? 'Could not save the conversion';
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final categories = context.watch<CategoryProvider>().categories;
    final rules = settings.unitConversions;
    final draft = _draft;
    final problem = _problem(draft, rules);
    final complete = _countController.text.trim().isNotEmpty && problem == null;
    final preview = complete ? _preview(draft, rules) : null;

    List<PickerItem> unitItems(String current) => [
      for (final unit in {
        ...settings.units,
        if (current.trim().isNotEmpty &&
            !settings.units.any((u) => sameLabel(u, current)))
          current,
      })
        PickerItem(value: unit, label: unit, icon: Icons.straighten_rounded),
    ];

    final categoryName = _categoryId.isEmpty
        ? 'Any category'
        : categories.where((c) => c.id == _categoryId).firstOrNull?.name ??
              'Deleted category';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.emptyIcon(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.rule == null ? 'Add conversion' : 'Edit conversion',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPri(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Leave a field on "Any" to cover every value of it.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSec(context)),
            ),
            const SizedBox(height: 20),
            _PickerField(
              label: 'Category',
              icon: Icons.category_rounded,
              value: categoryName,
              isAny: _categoryId.isEmpty,
              onTap: () => _pick(
                title: 'Category',
                selected: _categoryId,
                items: [
                  const PickerItem(value: '', label: 'Any category'),
                  for (final c in categories)
                    PickerItem(
                      value: c.id,
                      label: c.name,
                      icon: Icons.category_rounded,
                    ),
                ],
                onPicked: (v) => _categoryId = v,
              ),
            ),
            _PickerField(
              label: 'Brand',
              icon: Icons.business_rounded,
              value: _company.isEmpty ? 'Any brand' : _company,
              isAny: _company.isEmpty,
              onTap: () => _pick(
                title: 'Brand',
                selected: _company,
                items: [
                  const PickerItem(value: '', label: 'Any brand'),
                  for (final c in settings.companies)
                    PickerItem(
                      value: c,
                      label: c,
                      icon: Icons.business_rounded,
                    ),
                ],
                onPicked: (v) => _company = v,
              ),
            ),
            _PickerField(
              label: 'Sub-category',
              icon: Icons.label_rounded,
              value: _size.isEmpty ? 'Any sub-category' : _size,
              isAny: _size.isEmpty,
              onTap: () => _pick(
                title: 'Sub-category',
                selected: _size,
                items: [
                  const PickerItem(value: '', label: 'Any sub-category'),
                  for (final s in settings.sizes)
                    PickerItem(value: s, label: s, icon: Icons.label_rounded),
                ],
                onPicked: (v) => _size = v,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Conversion',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.textPri(context),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Glyph('1'),
                Expanded(
                  child: _PickerField(
                    label: 'Pack',
                    value: _packUnit,
                    onTap: () => _pick(
                      title: 'Pack unit',
                      selected: _packUnit,
                      items: unitItems(_packUnit),
                      canAddUnit: true,
                      onPicked: (v) => _packUnit = v,
                    ),
                  ),
                ),
                const _Glyph('='),
                SizedBox(
                  width: 76,
                  child: TextField(
                    controller: _countController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'How many',
                      hintText: '10',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PickerField(
                    label: 'Unit inside',
                    value: _baseUnit,
                    onTap: () => _pick(
                      title: 'Unit inside the pack',
                      selected: _baseUnit,
                      items: unitItems(_baseUnit),
                      canAddUnit: true,
                      onPicked: (v) => _baseUnit = v,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (problem != null || _saveError != null)
              Text(
                problem ?? _saveError!,
                style: const TextStyle(color: AppTheme.dangerColor),
              )
            else if (preview != null)
              Text(
                [
                  'Covers ${preview.covers} '
                      '${preview.covers == 1 ? 'product' : 'products'}',
                  if (preview.repack > 0) '${preview.repack} change pack size',
                  if (preview.convert > 0)
                    '${preview.convert} counted in $_packUnit — their stock '
                        'converts to $_baseUnit',
                ].join(' · '),
                style: TextStyle(color: AppTheme.textSec(context)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: complete && !_saving ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save and review'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "1" and "=" in "1 box = 10 pcs", sized to sit level with the fields.
class _Glyph extends StatelessWidget {
  const _Glyph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 8, 0),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPri(context),
      ),
    ),
  );
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.isAny = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData? icon;
  final bool isAny;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: icon == null ? null : Icon(icon),
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isAny
                  ? AppTheme.textSec(context)
                  : AppTheme.textPri(context),
            ),
          ),
        ),
      ),
    );
  }
}
