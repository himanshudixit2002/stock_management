import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/theme.dart';
import '../../models/product_model.dart';
import '../../providers/audit_log_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/unit_conversion_planner.dart';
import '../../services/unit_conversion_service.dart';
import '../../utils/currency.dart';
import '../../utils/responsive.dart';
import 'settings_context.dart';
import 'settings_page_shell.dart';

/// Shows what following the current conversions would do to [catalog], and
/// does it when asked. Resolves to true when anything was written.
///
/// Nothing a rule says reaches a product without passing through here, so
/// this is the one place that has to say what is about to happen: which packs
/// change, whose stock is re-counted, and what has to close first.
Future<bool?> showUnitConversionReview(
  BuildContext context, {
  required List<ProductModel> catalog,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    constraints: Responsive.sheetConstraints(context),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReviewSheet(catalog: catalog),
  );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.catalog});

  final List<ProductModel> catalog;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final UnitConversionService _service;
  bool _includeCustom = false;

  /// Open documents per product, or null while loading. Only looked up for an
  /// admin: nobody else may convert stock, and some of those collections are
  /// not readable without their own permissions.
  Map<String, List<String>>? _blockers;
  String? _blockerError;

  bool _applying = false;
  (int, int) _progress = (0, 0);
  UnitConversionReport? _report;

  @override
  void initState() {
    super.initState();
    _service = UnitConversionService(
      companyId: context.read<SettingsProvider>().companyId,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBlockers());
  }

  List<UnitChange> _plan({required bool includeCustom}) => planUnitChanges(
    widget.catalog,
    context.read<SettingsProvider>().unitConversions,
    includeCustom: includeCustom,
  );

  Future<void> _loadBlockers() async {
    if (!(context.read<AuthProvider>().currentUser?.isAdmin ?? false)) return;
    // Custom products too, so flipping "update these too" needs no reload.
    final ids = {
      for (final change in _plan(includeCustom: true))
        if (change.kind == UnitChangeKind.convertStock) change.product.id,
    };
    try {
      final blockers = ids.isEmpty
          ? <String, List<String>>{}
          : await _service.findBlockers(ids);
      if (mounted) setState(() => _blockers = blockers);
    } catch (e) {
      if (mounted) setState(() => _blockerError = '$e');
    }
  }

  Future<void> _apply(List<UnitChange> changes, int conversions) async {
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    if (conversions > 0) {
      final ok = await _confirmConversion(conversions);
      if (!ok || !mounted) return;
    }
    final audit = context.read<AuditLogProvider>();
    final products = context.read<ProductProvider>();
    setState(() {
      _applying = true;
      _progress = (0, changes.length);
    });
    final report = await _service.apply(
      changes,
      userId: user.uid,
      userName: user.name,
      onProgress: (done, total) {
        if (mounted) setState(() => _progress = (done, total));
      },
    );
    unawaited(
      audit.logAction(
        action: 'unit_conversions_applied',
        entityType: 'Settings',
        entityName: 'Unit conversions',
        userId: user.uid,
        userName: user.name,
        changes: {
          'packsChanged': report.repacked,
          'stockConverted': report.converted,
          'notChanged': report.failures.length,
        },
      ),
    );
    products.invalidateAnalytics();
    unawaited(products.refreshProducts());
    if (mounted) {
      setState(() {
        _applying = false;
        _report = report;
      });
    }
  }

  Future<bool> _confirmConversion(int count) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          count == 1
              ? 'Convert stock for 1 product?'
              : 'Convert stock for $count products?',
        ),
        content: const Text(
          'Their stock, holds, price lists, recipes and recurring invoices are '
          're-counted in the new unit, and each change is recorded in the '
          'product\'s stock history.\n\n'
          'Ask your team not to enter stock for these products while this '
          'runs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final readOnly = isInspectingWorkspace(context);
    final canConvert = user?.isAdmin ?? false;
    final canRepack =
        canConvert ||
        (user?.hasAnyPermission([
              AppPermissions.editProducts,
              AppPermissions.bulkEdit,
            ]) ??
            false);

    final changes = _plan(includeCustom: _includeCustom);
    final custom = _includeCustom
        ? 0
        : changes.where((c) => c.kind == UnitChangeKind.keptCustom).length;
    final customAvailable =
        _includeCustom ||
        changes.any((c) => c.kind == UnitChangeKind.keptCustom);
    List<UnitChange> ofKind(UnitChangeKind kind) =>
        changes.where((c) => c.kind == kind).toList();
    final repacks = ofKind(UnitChangeKind.repack);
    final conversions = ofKind(UnitChangeKind.convertStock);
    final mismatched = ofKind(UnitChangeKind.unitMismatch);
    final blockers = _blockers;
    final waiting = [
      if (blockers != null)
        for (final c in conversions)
          if (blockers[c.product.id] != null) c,
    ];
    final ready = [
      if (blockers != null)
        for (final c in conversions)
          if (blockers[c.product.id] == null) c,
    ];
    final toApply = [if (canRepack) ...repacks, if (canConvert) ...ready];

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.85,
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Text(
              _report == null ? 'Review changes' : 'Done',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPri(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _report == null
                  ? 'Nothing changes until you tap Update.'
                  : 'Products now follow your conversions.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSec(context)),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _report != null
                ? _ReportView(report: _report!)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    children: [
                      if (changes.isEmpty)
                        const SettingsNote(
                          text: 'Every product already follows its conversion.',
                          icon: Icons.check_circle_outline_rounded,
                          color: AppTheme.successColor,
                        ),
                      _Section(
                        title: 'Change pack size',
                        icon: Icons.inventory_2_rounded,
                        color: AppTheme.infoColor,
                        rows: [
                          for (final c in repacks)
                            (
                              c.product.name,
                              '${_packOf(c.product)} → '
                                  '${c.rule!.label}',
                            ),
                        ],
                      ),
                      _Section(
                        title: 'Convert stock',
                        icon: Icons.autorenew_rounded,
                        color: AppTheme.violetColor,
                        rows: [
                          for (final c in canConvert ? ready : conversions)
                            (c.product.name, _conversionOf(context, c)),
                        ],
                        trailing: canConvert && blockers == null
                            ? (_blockerError == null
                                  ? const LinearProgressIndicator()
                                  : Text(
                                      'Could not check open documents: '
                                      '$_blockerError',
                                      style: const TextStyle(
                                        color: AppTheme.dangerColor,
                                      ),
                                    ))
                            : null,
                      ),
                      if (conversions.isNotEmpty && !canConvert)
                        const SettingsNote(
                          text:
                              'Only an owner or admin can convert stock. The '
                              'pack changes above can still be applied.',
                          icon: Icons.lock_outline_rounded,
                          color: AppTheme.warningColor,
                        ),
                      if (canConvert && ready.isNotEmpty)
                        const SettingsNote(
                          text:
                              'Invoices, orders and returns from before the '
                              'conversion can no longer be cancelled or '
                              'returned automatically for these products — '
                              'their quantities are in the old unit. Adjust '
                              'stock by hand if you need to.',
                          icon: Icons.history_rounded,
                          color: AppTheme.warningColor,
                        ),
                      _Section(
                        title: 'Waiting for open documents',
                        icon: Icons.hourglass_top_rounded,
                        color: AppTheme.warningColor,
                        rows: [
                          for (final c in waiting)
                            (
                              c.product.name,
                              blockers![c.product.id]!.join(', '),
                            ),
                        ],
                        footnote:
                            'Receive, dispatch or cancel these first, then '
                            'come back.',
                      ),
                      if (customAvailable)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _includeCustom,
                          onChanged: (v) => setState(() => _includeCustom = v),
                          title: Text(
                            _includeCustom
                                ? 'Updating products with their own conversion'
                                : '$custom with their own conversion kept',
                          ),
                          subtitle: const Text(
                            'Set by hand on the product. Turn on to make them '
                            'follow these conversions too.',
                          ),
                        ),
                      _Section(
                        title: 'Counted in another unit',
                        icon: Icons.do_not_disturb_on_outlined,
                        color: AppTheme.textTer(context),
                        rows: [
                          for (final c in mismatched)
                            (
                              c.product.name,
                              'Counted in ${c.product.baseUnit}; '
                                  '${c.rule!.label} is for ${c.rule!.packUnit} '
                                  'or ${c.rule!.baseUnit}',
                            ),
                        ],
                        footnote: 'Left as they are.',
                      ),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: _report != null
                  ? FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _report!.repacked + _report!.converted > 0,
                      ),
                      child: const Text('Close'),
                    )
                  : _applying
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: _progress.$2 == 0
                              ? null
                              : _progress.$1 / _progress.$2,
                        ),
                        const SizedBox(height: 8),
                        Text('Updating ${_progress.$1} of ${_progress.$2}…'),
                      ],
                    )
                  : FilledButton(
                      onPressed: toApply.isEmpty || readOnly
                          ? null
                          : () => _apply(
                              toApply,
                              toApply
                                  .where(
                                    (c) =>
                                        c.kind == UnitChangeKind.convertStock,
                                  )
                                  .length,
                            ),
                      child: Text(
                        toApply.length == 1
                            ? 'Update 1 product'
                            : 'Update ${toApply.length} products',
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static String _packOf(ProductModel p) => p.hasPackUnit
      ? '1 ${p.packUnit} = ${p.unitsPerPack} ${p.baseUnit}'
      : 'no pack';

  static String _conversionOf(BuildContext context, UnitChange change) {
    final p = change.product;
    final rule = change.rule!;
    final f = change.factor;
    final stock =
        '${p.quantity} ${p.baseUnit} → ${p.quantity * f} ${rule.baseUnit}';
    if (p.sellingPrice <= 0) return stock;
    final before = Money.of(context, p.sellingPrice, listen: false);
    final after = Money.of(
      context,
      perUnitPrice(p.sellingPrice, f),
      listen: false,
    );
    return '$stock · $before/${p.baseUnit} → $after/${rule.baseUnit}';
  }
}

/// A titled, collapsible list of products with one line about each. Draws
/// nothing when there is nothing in it.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.color,
    required this.rows,
    this.trailing,
    this.footnote,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<(String, String)> rows;
  final Widget? trailing;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && trailing == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
      child: Theme(
        // ExpansionTile draws dividers above and below by default.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: rows.length <= 5,
          leading: Icon(icon, color: color),
          title: Text(
            '$title (${rows.length})',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: footnote == null || rows.isEmpty ? null : Text(footnote!),
          children: [
            ?trailing,
            for (final (name, detail) in rows)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 40),
                title: Text(name),
                subtitle: Text(detail),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});

  final UnitConversionReport report;

  @override
  Widget build(BuildContext context) {
    String products(int n) => n == 1 ? '1 product' : '$n products';
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      children: [
        if (report.repacked > 0)
          SettingsNote(
            text: 'Pack size changed on ${products(report.repacked)}.',
            icon: Icons.check_circle_outline_rounded,
            color: AppTheme.successColor,
          ),
        if (report.converted > 0)
          SettingsNote(
            text: 'Stock converted on ${products(report.converted)}.',
            icon: Icons.check_circle_outline_rounded,
            color: AppTheme.successColor,
          ),
        if (report.failures.isNotEmpty) ...[
          SettingsNote(
            text:
                '${products(report.failures.length)} left as they were. '
                'They still show on the conversions page, so you can try '
                'again.',
            icon: Icons.error_outline_rounded,
            color: AppTheme.warningColor,
          ),
          for (final entry in report.failures.entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(entry.key),
              subtitle: Text(entry.value),
            ),
        ],
      ],
    );
  }
}
