import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/plan_limits.dart';
import '../../config/theme.dart';
import '../../models/company_model.dart';
import '../../models/company_plan_model.dart';
import '../../providers/super_admin_provider.dart';
import '../../utils/date_formats.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/admin_search_bar.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/document_sheet.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';
import 'console_widgets.dart';
import 'inspection_banner.dart';
import 'plan_editor_dialog.dart';

/// One workspace, in full: what it holds, who is in it, what it is on, and the
/// lifecycle controls.
///
/// Every list here is read-only. A platform admin's write powers are lifecycle
/// only — plan, status, purge — and the security rules enforce that by granting
/// only read and delete under `companies/{id}`.
class SuperAdminCompanyScreen extends StatefulWidget {
  const SuperAdminCompanyScreen({super.key, required this.company});

  final CompanyModel company;

  @override
  State<SuperAdminCompanyScreen> createState() =>
      _SuperAdminCompanyScreenState();
}

class _SuperAdminCompanyScreenState extends State<SuperAdminCompanyScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = <_TabSpec>[
    _TabSpec('Overview', null),
    _TabSpec('Users', SuperAdminSection.users),
    _TabSpec('Roles', SuperAdminSection.roles),
    _TabSpec('Inventory', SuperAdminSection.products),
    _TabSpec('Stock ledger', SuperAdminSection.transactions),
    _TabSpec('Invoices', SuperAdminSection.invoices),
    _TabSpec('Sales orders', SuperAdminSection.salesOrders),
    _TabSpec('Purchase orders', SuperAdminSection.purchaseOrders),
    _TabSpec('Activity', SuperAdminSection.auditLogs),
    _TabSpec('Settings', null),
  ];

  late final TabController _tabController = TabController(
    length: _tabs.length,
    vsync: this,
  );

  /// Captured while the element is still active — see the note in
  /// SuperAdminShell: `dispose()` cannot reach an inherited widget.
  SuperAdminProvider? _provider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<SuperAdminProvider>();
  }

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_subscribeToVisibleTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SuperAdminProvider>().startWatchingCompanyDetail(
        widget.company.id,
      );
    });
  }

  /// Opens the stream for the tab being entered.
  ///
  /// The first version subscribed to all eight collections on open and left
  /// them running after the screen was popped; this pays for what is on screen.
  void _subscribeToVisibleTab() {
    if (!mounted) return;
    final section = _tabs[_tabController.index].section;
    if (section == null) return;
    context.read<SuperAdminProvider>().watchSection(section);
  }

  @override
  void dispose() {
    _tabController.removeListener(_subscribeToVisibleTab);
    _tabController.dispose();
    // Without this the detail streams outlived the screen. Scoped to this
    // company: the teardown runs a frame later, by which point another
    // workspace may already have bound its own streams.
    final provider = _provider;
    final companyId = widget.company.id;
    if (provider != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => provider.stopWatchingCompanyDetail(companyId),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();

    if (!provider.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workspace')),
        body: const EmptyStateWidget(
          icon: Icons.lock_rounded,
          title: 'Not available',
          subtitle: 'This area is restricted to platform administrators.',
        ),
      );
    }

    // Prefer the live document over the one the route was given, so a status or
    // plan change made here is reflected without popping the screen.
    final company = provider.companyById(widget.company.id) ?? widget.company;

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitleRow(
          icon: Icons.business_rounded,
          color: AppTheme.infoColor,
          title: company.displayName,
          subtitle: company.statusLabel,
        ),
        actions: [
          IconButton(
            tooltip: 'Open workspace (read-only)',
            icon: const Icon(Icons.visibility_rounded),
            onPressed: () => _openWorkspace(context, company),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          // Left-aligned so the first tabs sit where the eye starts and the
          // remaining ones visibly run off the edge; centred, ten tabs give no
          // hint that there is anything past the fold.
          tabAlignment: TabAlignment.start,
          labelColor: AppTheme.infoColor,
          unselectedLabelColor: AppTheme.textSec(context),
          indicatorColor: AppTheme.infoColor,
          tabs: [for (final tab in _tabs) Tab(text: tab.label)],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(company: company),
          _UsersTab(company: company),
          const _RolesTab(),
          const _ProductsTab(),
          const _TransactionsTab(),
          const _InvoicesTab(),
          const _SalesOrdersTab(),
          const _PurchaseOrdersTab(),
          const _AuditTab(),
          _SettingsTab(company: company),
        ],
      ),
    );
  }

  Future<void> _openWorkspace(
    BuildContext context,
    CompanyModel company,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Open ${company.displayName}?',
      message:
          'You will see the app exactly as this workspace does, with every '
          'create, edit and delete control hidden. The security rules refuse '
          'writes from a platform admin regardless. The visit is recorded in '
          'the platform audit log.',
      confirmLabel: 'Open read-only',
      icon: Icons.visibility_rounded,
      iconColor: AppTheme.infoColor,
    );
    if (!confirmed || !context.mounted) return;
    // Pop back to the shell first: the tenant app replaces this route stack.
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (!context.mounted) return;
    enterWorkspaceInspection(context, company);
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.section);
  final String label;
  final SuperAdminSection? section;
}

// -----------------------------------------------------------------------------
// Overview
// -----------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.company});

  final CompanyModel company;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();
    final failed = provider.statsFailedFor(company.id);
    final stats = failed
        ? null
        : provider.expandedStatsFor(company.id) ??
              provider.statsFor(company.id);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        16,
        Responsive.horizontalPadding(context),
        32,
      ),
      children: [
        _StatusCard(company: company),
        const ConsoleSectionTitle(
          title: 'Contents',
          icon: Icons.dataset_rounded,
          color: AppTheme.primaryColor,
        ),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: stats == null
              ? Text(failed ? 'Counts could not be read.' : 'Loading counts…')
              : Wrap(
                  spacing: 24,
                  runSpacing: 14,
                  children: [
                    _Count(
                      'Users',
                      stats.usersUnknown ? null : stats.users,
                    ),
                    _Count('Roles', stats.roles),
                    _Count('Products', stats.products),
                    _Count('Categories', stats.categories),
                    _Count('Invoices', stats.invoices),
                    _Count('Sales orders', stats.salesOrders),
                    _Count('Purchase orders', stats.purchaseOrders),
                    _Count('Transactions', stats.transactions),
                    _Count('Customers', stats.customers),
                    _Count('Vendors', stats.vendors),
                    _Count('Batches', stats.batches),
                    _Count('Returns', stats.returns),
                  ],
                ),
        ),
        const ConsoleSectionTitle(
          title: 'Plan',
          icon: Icons.workspace_premium_rounded,
          color: AppTheme.violetColor,
        ),
        _PlanCard(company: company, stats: stats),
        const ConsoleSectionTitle(
          title: 'Lifecycle',
          icon: Icons.warning_amber_rounded,
          color: AppTheme.dangerColor,
        ),
        _DangerZone(company: company),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value);

  final String label;

  /// Null renders as "—": a figure that could not be read, not a zero.
  final int? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value?.toString() ?? '—',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppTheme.textSec(context)),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.company});

  final CompanyModel company;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ConsoleBadge(
                label: company.statusLabel,
                color: statusColorOf(company.status),
              ),
              const SizedBox(width: 8),
              ConsoleBadge(
                label: company.plan.label,
                color: AppTheme.infoColor,
              ),
            ],
          ),
          if (company.statusNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              company.statusNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          _Row(label: 'Workspace id', value: company.id),
          _Row(
            label: 'Join code',
            value: company.permanentJoinCode.isEmpty
                ? '—'
                : company.permanentJoinCode,
          ),
          _Row(label: 'Owner uid', value: company.adminUid),
          _Row(
            label: 'Created',
            value: company.createdAt == null
                ? '—'
                : AppDates.dayTime.format(company.createdAt!),
          ),
          if (company.statusChangedAt != null)
            _Row(
              label: 'Status changed',
              value: AppDates.dayTime.format(company.statusChangedAt!),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.company, required this.stats});

  final CompanyModel company;
  final CompanyStats? stats;

  @override
  Widget build(BuildContext context) {
    final plan = company.plan;
    final results = stats == null
        ? const <PlanLimitResult>[]
        : PlanLimits.checkAll(plan, planUsageOf(stats!));

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              ConsoleBadge(
                label: CompanyPlan.statusLabel(plan.status),
                color: plan.isActive
                    ? AppTheme.successColor
                    : AppTheme.dangerColor,
              ),
              IconButton(
                tooltip: 'Change plan',
                icon: const Icon(Icons.edit_rounded, size: 18),
                onPressed: () => showPlanEditor(context, company),
              ),
            ],
          ),
          Text(
            plan.definition.description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (plan.startedAt != null)
            _Row(
              label: 'On this plan since',
              value: AppDates.day.format(plan.startedAt!),
            ),
          if (plan.trialEndsAt != null)
            _Row(
              label: plan.trialExpired ? 'Trial ended' : 'Trial ends',
              value: AppDates.day.format(plan.trialEndsAt!),
            ),
          if (plan.note.isNotEmpty) _Row(label: 'Note', value: plan.note),
          if (plan.limitOverrides.isNotEmpty)
            _Row(
              label: 'Overrides',
              value: plan.limitOverrides.entries
                  .map(
                    (e) =>
                        '${PlanLimitKeys.labelOf(e.key)} '
                        '${e.value < 0 ? 'unlimited' : e.value}',
                  )
                  .join(', '),
            ),
          const SizedBox(height: 8),
          if (stats == null)
            Text(
              'Counts still loading — usage against the plan will appear here.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else if (results.every((r) => !r.isCapped))
            Text(
              'This tier applies no limits.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textSec(context)),
            )
          else
            for (final result in results.where((r) => r.isCapped))
              ConsoleMeter(
                label: result.label,
                valueText: result.usageText,
                fraction: result.fraction,
                color: switch (result.state) {
                  PlanLimitState.blocked => AppTheme.dangerColor,
                  PlanLimitState.warning => AppTheme.warningColor,
                  PlanLimitState.ok => AppTheme.successColor,
                },
              ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// List tabs
// -----------------------------------------------------------------------------

/// A searchable, read-only view of one company subcollection.
///
/// Every list tab is this widget with a different projection, so none of them
/// can drift into skipping the loading/empty/error triad or the document sheet.
class _SectionList extends StatefulWidget {
  const _SectionList({
    required this.section,
    required this.hintText,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.searchFields,
    required this.titleOf,
    required this.subtitleOf,
    this.trailingOf,
    this.icon,
    this.iconColor,
  });

  final SuperAdminSection section;
  final String hintText;
  final IconData emptyIcon;
  final String emptyTitle;

  /// Document keys the search box matches against.
  final List<String> searchFields;

  final String Function(Map<String, dynamic>) titleOf;
  final String Function(Map<String, dynamic>) subtitleOf;
  final Widget? Function(BuildContext, Map<String, dynamic>)? trailingOf;
  final IconData? icon;
  final Color? iconColor;

  @override
  State<_SectionList> createState() => _SectionListState();
}

class _SectionListState extends State<_SectionList> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Also subscribed by the tab controller listener; watchSection is
    // idempotent, and this covers the tab that is selected on open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SuperAdminProvider>().watchSection(widget.section);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();
    final all = provider.sectionData(widget.section);
    final q = _query.toLowerCase();
    final visible = q.isEmpty
        ? all
        : all
              .where(
                (row) => widget.searchFields.any(
                  (field) =>
                      (row[field]?.toString().toLowerCase() ?? '').contains(q),
                ),
              )
              .toList();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            Responsive.horizontalPadding(context),
            12,
            Responsive.horizontalPadding(context),
            0,
          ),
          child: AdminSearchBar<void, void>(
            hintText: widget.hintText,
            onChanged: (v) => setState(() => _query = v),
            trailing: [
              IconButton(
                tooltip: 'Copy visible rows',
                icon: const Icon(Icons.copy_all_rounded),
                onPressed: () => copyRowsAsTsv(
                  context,
                  headers: const ['Id', 'Title', 'Detail'],
                  rows: [
                    for (final row in visible)
                      [
                        row['id']?.toString() ?? '',
                        widget.titleOf(row),
                        widget.subtitleOf(row).replaceAll('\n', ' · '),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ConsoleListState(
            isLoading: provider.sectionLoading(widget.section),
            error: provider.sectionError(widget.section),
            isEmpty: visible.isEmpty,
            emptyIcon: widget.emptyIcon,
            emptyTitle: all.isEmpty ? widget.emptyTitle : 'Nothing matches',
            emptySubtitle: all.isEmpty
                ? 'This workspace has none.'
                : 'Try a different search.',
            onRetry: () => context.read<SuperAdminProvider>().retrySection(
              widget.section,
            ),
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                Responsive.horizontalPadding(context),
                12,
                Responsive.horizontalPadding(context),
                32,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final row = visible[i];
                return ConsoleDocTile(
                  index: i,
                  data: row,
                  icon: widget.icon,
                  iconColor: widget.iconColor,
                  title: widget.titleOf(row),
                  subtitle: widget.subtitleOf(row),
                  trailing: widget.trailingOf?.call(context, row),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

String _str(Map<String, dynamic> row, String key, [String fallback = '—']) {
  final value = row[key];
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String _when(Map<String, dynamic> row, String key) {
  final value = row[key];
  return value is Timestamp ? AppDates.dayTime.format(value.toDate()) : '—';
}

class _UsersTab extends StatelessWidget {
  const _UsersTab({required this.company});

  final CompanyModel company;

  @override
  Widget build(BuildContext context) {
    return _SectionList(
      section: SuperAdminSection.users,
      hintText: 'Search members by name, email, or uid',
      emptyIcon: Icons.people_outline_rounded,
      emptyTitle: 'No members',
      searchFields: const ['name', 'email', 'id', 'role'],
      icon: Icons.person_rounded,
      iconColor: AppTheme.indigoColor,
      titleOf: (row) => _str(row, 'name', 'Unnamed user'),
      subtitleOf: (row) =>
          '${_str(row, 'email', 'no email')}\n'
          '${_str(row, 'id', '')}'
          '${row['id'] == company.adminUid ? '  ·  owner' : ''}',
      trailingOf: (context, row) {
        final role = _str(row, 'role', '').toUpperCase();
        return role.isEmpty || role == '—'
            ? null
            : ConsoleBadge(label: role, color: AppTheme.accentColor);
      },
    );
  }
}

class _RolesTab extends StatelessWidget {
  const _RolesTab();

  @override
  Widget build(BuildContext context) {
    return _SectionList(
      section: SuperAdminSection.roles,
      hintText: 'Search roles',
      emptyIcon: Icons.shield_outlined,
      emptyTitle: 'No roles',
      searchFields: const ['name', 'id', 'description'],
      icon: Icons.shield_rounded,
      iconColor: AppTheme.violetColor,
      titleOf: (row) => _str(row, 'name', 'Unnamed role'),
      subtitleOf: (row) {
        final permissions = row['permissions'];
        final granted = permissions is Map
            ? permissions.values.where((v) => v == true).length
            : 0;
        return '${_str(row, 'description', 'No description')}\n'
            '$granted permissions granted';
      },
      trailingOf: (context, row) => row['isSystem'] == true
          ? const ConsoleBadge(label: 'SYSTEM', color: AppTheme.infoColor)
          : null,
    );
  }
}

class _ProductsTab extends StatelessWidget {
  const _ProductsTab();

  @override
  Widget build(BuildContext context) {
    return _SectionList(
      section: SuperAdminSection.products,
      hintText: 'Search products by name, barcode, or category',
      emptyIcon: Icons.inventory_2_outlined,
      emptyTitle: 'No products',
      searchFields: const ['name', 'barcode', 'categoryName', 'id'],
      icon: Icons.inventory_2_rounded,
      iconColor: AppTheme.primaryColor,
      titleOf: (row) => _str(row, 'name', 'Unnamed product'),
      subtitleOf: (row) =>
          '${_str(row, 'categoryName', 'Uncategorised')}  ·  '
          '${_str(row, 'quantity', '0')} ${_str(row, 'unit', '')}\n'
          'Updated ${_when(row, 'updatedAt')}',
    );
  }
}

class _TransactionsTab extends StatelessWidget {
  const _TransactionsTab();

  @override
  Widget build(BuildContext context) {
    return _SectionList(
      section: SuperAdminSection.transactions,
      hintText: 'Search the stock ledger',
      emptyIcon: Icons.swap_vert_rounded,
      emptyTitle: 'No stock movements',
      searchFields: const ['productName', 'type', 'location', 'userName'],
      icon: Icons.swap_vert_rounded,
      iconColor: AppTheme.cyanColor,
      titleOf: (row) =>
          '${_str(row, 'type', 'movement')}  ·  ${_str(row, 'productName', '')}',
      subtitleOf: (row) =>
          'Qty ${_str(row, 'quantity', '0')} at ${_str(row, 'location', '—')}\n'
          '${_str(row, 'userName', 'unknown user')}  ·  ${_when(row, 'date')}',
    );
  }
}

class _InvoicesTab extends StatelessWidget {
  const _InvoicesTab();

  @override
  Widget build(BuildContext context) {
    return _SectionList(
      section: SuperAdminSection.invoices,
      hintText: 'Search invoices by number or party',
      emptyIcon: Icons.receipt_long_outlined,
      emptyTitle: 'No invoices',
      searchFields: const [
        'invoiceNumber',
        'customerName',
        'vendorName',
        'id',
      ],
      icon: Icons.receipt_long_rounded,
      iconColor: AppTheme.warningColor,
      titleOf: (row) => _str(row, 'invoiceNumber', 'Invoice'),
      subtitleOf: (row) =>
          '${_str(row, 'customerName', _str(row, 'vendorName', 'No party'))}\n'
          'Total ${_str(row, 'total', _str(row, 'grandTotal', '—'))}  ·  '
          '${_when(row, 'createdAt')}',
      trailingOf: (context, row) {
        final status = _str(row, 'status', '').toUpperCase();
        return status == '—' || status.isEmpty
            ? null
            : ConsoleBadge(label: status, color: AppTheme.infoColor);
      },
    );
  }
}

class _SalesOrdersTab extends StatelessWidget {
  const _SalesOrdersTab();

  @override
  Widget build(BuildContext context) {
    return _SectionList(
      section: SuperAdminSection.salesOrders,
      hintText: 'Search sales orders',
      emptyIcon: Icons.local_shipping_outlined,
      emptyTitle: 'No sales orders',
      searchFields: const ['orderNumber', 'customerName', 'status', 'id'],
      icon: Icons.local_shipping_rounded,
      iconColor: AppTheme.successColor,
      titleOf: (row) => _str(row, 'orderNumber', 'Sales order'),
      subtitleOf: (row) =>
          '${_str(row, 'customerName', 'No customer')}\n'
          'Total ${_str(row, 'totalAmount', '—')}  ·  ${_when(row, 'createdAt')}',
      trailingOf: (context, row) {
        final status = _str(row, 'status', '').toUpperCase();
        return status == '—' || status.isEmpty
            ? null
            : ConsoleBadge(label: status, color: AppTheme.successColor);
      },
    );
  }
}

class _PurchaseOrdersTab extends StatelessWidget {
  const _PurchaseOrdersTab();

  @override
  Widget build(BuildContext context) {
    return _SectionList(
      section: SuperAdminSection.purchaseOrders,
      hintText: 'Search purchase orders',
      emptyIcon: Icons.shopping_cart_outlined,
      emptyTitle: 'No purchase orders',
      searchFields: const ['orderNumber', 'vendorName', 'status', 'id'],
      icon: Icons.shopping_cart_rounded,
      iconColor: AppTheme.indigoColor,
      titleOf: (row) => _str(row, 'orderNumber', 'Purchase order'),
      subtitleOf: (row) =>
          '${_str(row, 'vendorName', 'No vendor')}\n'
          'Total ${_str(row, 'totalAmount', '—')}  ·  ${_when(row, 'createdAt')}',
      trailingOf: (context, row) {
        final status = _str(row, 'status', '').toUpperCase();
        return status == '—' || status.isEmpty
            ? null
            : ConsoleBadge(label: status, color: AppTheme.indigoColor);
      },
    );
  }
}

class _AuditTab extends StatelessWidget {
  const _AuditTab();

  @override
  Widget build(BuildContext context) {
    return _SectionList(
      section: SuperAdminSection.auditLogs,
      hintText: 'Search this workspace\'s activity',
      emptyIcon: Icons.history_rounded,
      emptyTitle: 'No activity recorded',
      searchFields: const ['action', 'entityType', 'entityName', 'userName'],
      icon: Icons.bolt_rounded,
      iconColor: AppTheme.accentColor,
      titleOf: (row) =>
          '${_str(row, 'action', 'action')}  ·  ${_str(row, 'entityName', _str(row, 'entityType', ''))}',
      subtitleOf: (row) =>
          '${_str(row, 'userName', 'unknown user')}\n${_when(row, 'timestamp')}',
    );
  }
}

// -----------------------------------------------------------------------------
// Settings
// -----------------------------------------------------------------------------

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.company});

  final CompanyModel company;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();
    final settings = provider.companySettings;

    // A null map used to mean all three of loading, failed, and genuinely
    // absent — so every visit flashed "No settings stored" before the read
    // landed, and a denied read said it permanently.
    if (provider.companySettingsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.companySettingsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            provider.companySettingsError!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    if (settings == null) {
      return const EmptyStateWidget(
        icon: Icons.tune_rounded,
        title: 'No settings stored',
        subtitle:
            'This workspace has never saved a settings map, so it is running '
            'on defaults.',
      );
    }

    // Rendered from the raw map rather than a hand-picked handful of keys: the
    // billing model alone carries ~25 fields and grows, and a curated list goes
    // stale silently.
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Responsive.horizontalPadding(context),
        16,
        Responsive.horizontalPadding(context),
        32,
      ),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Workspace settings',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${settings.length} keys stored on the company document.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => showDocumentSheet(
                  context,
                  title: 'Settings',
                  subtitle: company.displayName,
                  data: settings,
                ),
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                label: const Text('View all settings'),
              ),
            ],
          ),
        ),
        const ConsoleSectionTitle(title: 'Values', icon: Icons.tune_rounded),
        for (final key in settings.keys.toList()..sort())
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GlassPanel(
              padding: const EdgeInsets.all(12),
              child: _Row(
                label: key,
                value: formatDocumentValue(settings[key]),
              ),
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Lifecycle
// -----------------------------------------------------------------------------

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.company});

  final CompanyModel company;

  Future<void> _setStatus(
    BuildContext context,
    CompanyStatus status,
    String note,
  ) async {
    final provider = context.read<SuperAdminProvider>();
    final ok = await provider.setStatus(
      companyId: company.id,
      status: status,
      note: note,
    );
    if (!context.mounted) return;
    if (ok) {
      showSuccessSnackBar(context, 'Workspace ${status.name}');
    } else {
      showErrorSnackBar(context, provider.errorMessage ?? 'Update failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Suspending stops this workspace writing new data. Its members '
              'keep read access and see the reason.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            if (company.isActive)
              _ActionButton(
                icon: Icons.pause_circle_rounded,
                label: 'Suspend workspace',
                color: AppTheme.warningColor,
                onPressed: () async {
                  final confirmed = await showConfirmDialog(
                    context,
                    title: 'Suspend workspace?',
                    message:
                        '${company.displayName} will stop being able to add '
                        'or change data. This is reversible.',
                    confirmLabel: 'Suspend',
                  );
                  if (!confirmed || !context.mounted) return;
                  await _setStatus(
                    context,
                    CompanyStatus.suspended,
                    'Suspended by platform admin',
                  );
                },
              ),

            if (company.isSuspended)
              _ActionButton(
                icon: Icons.play_circle_rounded,
                label: 'Reactivate workspace',
                color: AppTheme.successColor,
                onPressed: () => _setStatus(context, CompanyStatus.active, ''),
              ),

            if (!company.isDeleted) ...[
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.delete_outline_rounded,
                label: 'Delete workspace',
                color: AppTheme.dangerColor,
                onPressed: () async {
                  final ok = await _confirmByName(
                    context,
                    title: 'Delete workspace?',
                    message:
                        'This marks ${company.displayName} deleted and revokes '
                        'access immediately. Data is kept and this can be '
                        'undone.',
                    company: company,
                    confirmLabel: 'Delete',
                  );
                  if (!ok || !context.mounted) return;
                  await _setStatus(
                    context,
                    CompanyStatus.deleted,
                    'Deleted by platform admin',
                  );
                },
              ),
            ],

            if (company.isDeleted) ...[
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.restore_from_trash_rounded,
                label: 'Restore workspace',
                color: AppTheme.successColor,
                onPressed: () => _setStatus(context, CompanyStatus.active, ''),
              ),
              const Divider(height: 24),
              Text(
                'Permanently erase everything in this workspace. There are no '
                'backups on this project — this cannot be undone.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.dangerColor),
              ),
              const SizedBox(height: 8),
              _ActionButton(
                icon: Icons.local_fire_department_rounded,
                label: 'Purge permanently',
                color: AppTheme.dangerColor,
                onPressed: () => _purge(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _purge(BuildContext context) async {
    final ok = await _confirmByName(
      context,
      title: 'Purge permanently?',
      message:
          'Every product, invoice, order and ledger entry in '
          '${company.displayName} will be erased. There are no backups. This '
          'cannot be undone.',
      company: company,
      confirmLabel: 'Purge forever',
    );
    if (!ok || !context.mounted) return;

    final provider = context.read<SuperAdminProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final progress = ValueNotifier<String>('Starting…');

    // Captured from the dialog's own builder so the dismissal below pops the
    // dialog rather than whatever route happens to be on top. The previous
    // version used positional `navigator.canPop()` guesses, so a hardware back
    // press during the purge popped the company screen and then the console —
    // ejecting the admin from the middle of an irreversible operation.
    BuildContext? dialogContext;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogContext = ctx;
          // barrierDismissible alone does not stop the Android back gesture.
          return PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: progress,
                      builder: (_, text, _) => Text(text),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    // The service reports progress per collection; a purge on a large tenant
    // takes minutes, and a blind spinner gives no way to tell it apart from a
    // hang.
    final purged = await provider.purgeCompany(
      companyId: company.id,
      onProgress: (collection, deleted) =>
          progress.value = 'Purging $collection… $deleted deleted',
    );

    final ctx = dialogContext;
    if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
    // Disposed only after the dialog is gone: while it was still listening,
    // a late onProgress callback wrote to a disposed notifier.
    progress.dispose();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          purged ? 'Workspace purged' : provider.errorMessage ?? 'Purge failed',
        ),
      ),
    );
    // Leave the (now deleted) workspace screen behind on success.
    if (purged && navigator.canPop()) navigator.pop();
  }

  Future<bool> _confirmByName(
    BuildContext context, {
    required String title,
    required String message,
    required CompanyModel company,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    final expected = company.displayName.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final matches = controller.text.trim() == expected;
          return AlertDialog(
            // Scrollable because the field autofocuses: the keyboard always
            // opens over this dialog, and a fixed Column overflowed on every
            // standard phone — on the delete and purge confirmations of all
            // places.
            scrollable: true,
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 16),
                Text(
                  'Type "$expected" to confirm:',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.dangerColor,
                ),
                onPressed: matches ? () => Navigator.pop(ctx, true) : null,
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result == true;
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            flex: 3,
            child: SelectableText(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
