import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../models/company_model.dart';
import '../../../models/company_plan_model.dart';
import '../../../providers/super_admin_provider.dart';
import '../../../utils/date_formats.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/admin_search_bar.dart';
import '../../../widgets/animations.dart';
import '../../../widgets/glass_panel.dart';
import '../console_widgets.dart';

/// How the workspace list is ordered.
enum WorkspaceSort {
  newest('Newest first'),
  name('Name (A–Z)'),
  users('Most users'),
  products('Most products'),
  invoices('Most invoices');

  const WorkspaceSort(this.label);
  final String label;
}

/// Every tenant, searchable and sortable, with bulk lifecycle actions.
class WorkspacesSection extends StatefulWidget {
  const WorkspacesSection({super.key});

  @override
  State<WorkspacesSection> createState() => _WorkspacesSectionState();
}

class _WorkspacesSectionState extends State<WorkspacesSection> {
  String _query = '';
  CompanyStatus? _statusFilter;
  String? _planFilter;
  WorkspaceSort _sort = WorkspaceSort.newest;
  final Set<String> _selected = {};

  /// Whether the list is in selection mode.
  ///
  /// Long-press alone was the only way in — undiscoverable, and unreachable
  /// with switch access or a keyboard. The toolbar toggle is the primary
  /// affordance; long-press stays as a shortcut.
  bool _selectMode = false;

  /// True while a bulk lifecycle change is running, so the bar cannot be fired
  /// twice and looks busy rather than frozen.
  bool _bulkBusy = false;

  List<CompanyModel> _visible(SuperAdminProvider provider) {
    final q = _query.toLowerCase();
    final list = provider.companies.where((c) {
      if (_statusFilter != null && c.status != _statusFilter) return false;
      if (_planFilter != null && c.plan.planId != _planFilter) return false;
      if (q.isEmpty) return true;
      return c.companyName.toLowerCase().contains(q) ||
          c.id.toLowerCase().contains(q) ||
          c.adminUid.toLowerCase().contains(q) ||
          c.permanentJoinCode.toLowerCase().contains(q);
    }).toList();

    int statOf(CompanyModel c, int Function(CompanyStats) pick) {
      final stats = provider.statsFor(c.id);
      return stats == null ? -1 : pick(stats);
    }

    switch (_sort) {
      case WorkspaceSort.newest:
        // watchCompanies already returns createdAt desc.
        break;
      case WorkspaceSort.name:
        list.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      case WorkspaceSort.users:
        list.sort(
          (a, b) =>
              statOf(b, (s) => s.users).compareTo(statOf(a, (s) => s.users)),
        );
      case WorkspaceSort.products:
        list.sort(
          (a, b) => statOf(
            b,
            (s) => s.products,
          ).compareTo(statOf(a, (s) => s.products)),
        );
      case WorkspaceSort.invoices:
        list.sort(
          (a, b) => statOf(
            b,
            (s) => s.invoices,
          ).compareTo(statOf(a, (s) => s.invoices)),
        );
    }
    return list;
  }

  /// Drops selected ids that the current filters have hidden.
  ///
  /// Without this, changing a filter left "3 selected" on screen while the
  /// bulk action operated on workspaces the admin could no longer see.
  void _reconcileSelection(List<CompanyModel> visible) {
    if (_selected.isEmpty) return;
    final visibleIds = visible.map((c) => c.id).toSet();
    _selected.removeWhere((id) => !visibleIds.contains(id));
  }

  Future<void> _bulkStatus(
    SuperAdminProvider provider,
    CompanyStatus status,
  ) async {
    if (_bulkBusy) return;
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final verb = status == CompanyStatus.active ? 'Reactivate' : 'Suspend';
    final confirmed = await showConfirmDialog(
      context,
      title: '$verb ${ids.length} workspaces?',
      message: status == CompanyStatus.active
          ? 'They will be able to write data again immediately.'
          : 'They keep read access to their own books but cannot write new '
                'data until reactivated.',
      confirmLabel: verb,
      icon: status == CompanyStatus.active
          ? Icons.play_circle_rounded
          : Icons.pause_circle_rounded,
      iconColor: status == CompanyStatus.active
          ? AppTheme.successColor
          : AppTheme.warningColor,
    );
    if (!confirmed) return;

    setState(() => _bulkBusy = true);
    var failed = 0;
    for (final id in ids) {
      final ok = await provider.setStatus(
        companyId: id,
        status: status,
        note: 'Bulk $verb from the platform console',
      );
      if (!ok) failed++;
    }
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selectMode = false;
      _bulkBusy = false;
    });
    if (failed == 0) {
      showSuccessSnackBar(context, '${ids.length} workspaces updated');
    } else {
      showErrorSnackBar(context, '$failed of ${ids.length} could not be updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();
    final companies = provider.companies;
    final visible = _visible(provider);
    _reconcileSelection(visible);
    final pad = Responsive.horizontalPadding(context);
    final narrow = Responsive.isMobile(context);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
          child: AdminSearchBar<CompanyStatus?, WorkspaceSort>(
            hintText: 'Search by name, id, join code, or owner uid',
            onChanged: (v) => setState(() => _query = v),
            selectedFilter: _statusFilter,
            onFilterChanged: (v) => setState(
              () => _statusFilter = v == _statusFilter ? null : v,
            ),
            filters: [
              const AdminFilter(value: null, label: 'All'),
              for (final status in CompanyStatus.values)
                AdminFilter(
                  value: status,
                  label: CompanyModel.statusToString(status).toUpperCase(),
                  count: companies.where((c) => c.status == status).length,
                ),
            ],
            selectedSort: _sort,
            onSortChanged: (v) => setState(() => _sort = v),
            sorts: [
              for (final sort in WorkspaceSort.values)
                AdminFilter(value: sort, label: sort.label),
            ],
            trailing: [
              IconButton(
                tooltip: _selectMode ? 'Exit selection' : 'Select workspaces',
                isSelected: _selectMode,
                icon: Icon(
                  _selectMode
                      ? Icons.check_circle_rounded
                      : Icons.checklist_rounded,
                ),
                onPressed: () => setState(() {
                  _selectMode = !_selectMode;
                  if (!_selectMode) _selected.clear();
                }),
              ),
              IconButton(
                tooltip: 'Copy visible rows',
                icon: const Icon(Icons.copy_all_rounded),
                onPressed: () => copyRowsAsTsv(
                  context,
                  headers: const [
                    'Workspace',
                    'Id',
                    'Status',
                    'Plan',
                    'Users',
                    'Products',
                    'Invoices',
                    'Created',
                  ],
                  rows: [
                    for (final c in visible)
                      [
                        c.displayName,
                        c.id,
                        c.statusLabel,
                        c.plan.label,
                        provider.statsFor(c.id)?.users.toString() ?? '',
                        provider.statsFor(c.id)?.products.toString() ?? '',
                        provider.statsFor(c.id)?.invoices.toString() ?? '',
                        c.createdAt == null
                            ? ''
                            : AppDates.isoDay.format(c.createdAt!),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Any plan'),
                  selected: _planFilter == null,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _planFilter = null),
                ),
                for (final plan in PlanCatalog.all)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(
                        '${plan.label} '
                        '(${companies.where((c) => c.plan.planId == plan.id).length})',
                      ),
                      selected: _planFilter == plan.id,
                      showCheckmark: false,
                      onSelected: (_) => setState(
                        () => _planFilter = _planFilter == plan.id
                            ? null
                            : plan.id,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_selected.isNotEmpty)
          Container(
            margin: EdgeInsets.fromLTRB(pad, 12, pad, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.infoColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            // Wrap, not Row: the label plus two labelled buttons plus a close
            // icon needed ~330px inside 304px at 360dp.
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '${_selected.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_bulkBusy)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  _BulkAction(
                    icon: Icons.play_arrow_rounded,
                    label: 'Reactivate',
                    compact: narrow,
                    onPressed: () =>
                        _bulkStatus(provider, CompanyStatus.active),
                  ),
                  _BulkAction(
                    icon: Icons.pause_rounded,
                    label: 'Suspend',
                    compact: narrow,
                    onPressed: () =>
                        _bulkStatus(provider, CompanyStatus.suspended),
                  ),
                  IconButton(
                    tooltip: 'Clear selection',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() {
                      _selected.clear();
                      _selectMode = false;
                    }),
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: ConsoleListState(
            isLoading: provider.isLoading && companies.isEmpty,
            // The company stream's own error only. provider.errorMessage is the
            // shared *mutation* error, so a failed bulk suspend used to blank
            // the entire workspace list.
            error: companies.isEmpty ? provider.errorMessage : null,
            isEmpty: visible.isEmpty,
            emptyIcon: Icons.business_rounded,
            emptyTitle: companies.isEmpty
                ? 'No workspaces yet'
                : 'Nothing matches',
            emptySubtitle: companies.isEmpty
                ? 'Workspaces appear here as soon as they are created.'
                : 'Try a different search, status, or plan.',
            onRetry: () {
              provider.clearError();
              provider.startWatching();
            },
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
              itemCount: visible.length,
              itemBuilder: (context, i) => _CompanyTile(
                company: visible[i],
                selected: _selected.contains(visible[i].id),
                selectionActive: _selectMode || _selected.isNotEmpty,
                onToggle: () => setState(() {
                  final id = visible[i].id;
                  _selected.contains(id)
                      ? _selected.remove(id)
                      : _selected.add(id);
                  if (_selected.isNotEmpty) _selectMode = true;
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompanyTile extends StatefulWidget {
  const _CompanyTile({
    required this.company,
    required this.selected,
    required this.selectionActive,
    required this.onToggle,
  });

  final CompanyModel company;
  final bool selected;
  final bool selectionActive;
  final VoidCallback onToggle;

  @override
  State<_CompanyTile> createState() => _CompanyTileState();
}

class _CompanyTileState extends State<_CompanyTile> {
  @override
  void initState() {
    super.initState();
    // Fetched here rather than scheduled from build(): the tile watches the
    // provider, so the old placement re-ran for every visible tile on every
    // notification and was saved from looping only by the provider's dedupe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SuperAdminProvider>().loadStats(widget.company.id);
    });
  }

  @override
  void didUpdateWidget(_CompanyTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company.id != widget.company.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<SuperAdminProvider>().loadStats(widget.company.id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = widget.company;
    final selected = widget.selected;
    final selectionActive = widget.selectionActive;
    final onToggle = widget.onToggle;
    // select() so a tile rebuilds only when its own counts change, not on
    // every provider notification across the estate.
    final stats = context.select<SuperAdminProvider, CompanyStats?>(
      (p) => p.statsFailedFor(company.id) ? null : p.statsFor(company.id),
    );
    final statsFailed = context.select<SuperAdminProvider, bool>(
      (p) => p.statsFailedFor(company.id),
    );

    final initials = company.displayName.trim().isNotEmpty
        ? company.displayName.trim()[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      // Long-press starts a selection; once one is active a tap extends it, so
      // bulk actions never need a separate "select mode" toggle. The gesture
      // wrapper is outside PlayfulPressable, which handles taps only.
      child: GestureDetector(
        onLongPress: onToggle,
        child: PlayfulPressable(
        onTap: () => selectionActive
            ? onToggle()
            : Navigator.pushNamed(
                context,
                AppRoutes.superAdminCompany,
                arguments: company,
              ),
        child: GlassPanel(
          border: selected
              ? Border.all(color: AppTheme.infoColor, width: 1.5)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: AppTheme.heroGrad(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              color: AppTheme.onGradient,
                            )
                          : Text(
                              initials,
                              style: const TextStyle(
                                color: AppTheme.onGradient,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            company.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              ConsoleBadge(
                                label: company.plan.label,
                                color: AppTheme.infoColor,
                              ),
                              if (!company.isActive)
                                ConsoleBadge(
                                  label: company.statusLabel,
                                  color: statusColorOf(company.status),
                                ),
                              if (company.plan.status != PlanStatus.active)
                                ConsoleBadge(
                                  label: CompanyPlan.statusLabel(
                                    company.plan.status,
                                  ),
                                  color: AppTheme.dangerColor,
                                ),
                              if (company.plan.isOnTrial)
                                const ConsoleBadge(
                                  label: 'TRIAL',
                                  color: AppTheme.violetColor,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.iconMute(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.dividerC(context).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  // Expanded per stat: four unflexed counts in a spaceBetween
                  // Row overflowed at 360dp, and at any text scale above 1.
                  child: Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                          icon: Icons.people_rounded,
                          // A count that could not be read shows as unknown, not
                          // as 0 — a confident zero here is what hid the rules
                          // gap in the first place.
                          value: stats == null
                              ? (statsFailed ? '—' : '–')
                              : (stats.usersUnknown
                                    ? '—'
                                    : stats.users.toString()),
                        ),
                      ),
                      Expanded(
                        child: _MiniStat(
                          icon: Icons.inventory_2_rounded,
                          value: stats?.products.toString() ??
                              (statsFailed ? '—' : '–'),
                        ),
                      ),
                      Expanded(
                        child: _MiniStat(
                          icon: Icons.receipt_rounded,
                          value: stats?.invoices.toString() ??
                              (statsFailed ? '—' : '–'),
                        ),
                      ),
                      Expanded(
                        child: _MiniStat(
                          icon: Icons.shopping_cart_rounded,
                          value: stats == null
                              ? (statsFailed ? '—' : '–')
                              : '${stats.salesOrders + stats.purchaseOrders}',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Owner: ${company.adminUid}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textTer(context),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (company.createdAt != null)
                      Text(
                        AppDates.day.format(company.createdAt!),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textTer(context),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

/// A bulk lifecycle button that drops its label on a narrow screen.
class _BulkAction extends StatelessWidget {
  const _BulkAction({
    required this.icon,
    required this.label,
    required this.compact,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: label,
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSec(context)),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.textPri(context),
            ),
          ),
        ),
      ],
    );
  }
}
