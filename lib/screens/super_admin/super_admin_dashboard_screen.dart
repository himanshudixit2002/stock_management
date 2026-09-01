import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/company_model.dart';
import '../../providers/super_admin_provider.dart';
import '../../utils/date_formats.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';

/// Every workspace on the platform, for the operator of the platform.
///
/// This is the one screen that deliberately crosses the tenant boundary the
/// rest of the app is fenced inside, so it is only reachable when
/// [SuperAdminProvider.isSuperAdmin] is true — and the rules enforce the same
/// thing independently.
class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  CompanyStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    // Safe to call repeatedly; the provider ignores a second subscription.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SuperAdminProvider>().startWatching();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();

    if (!provider.isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Super Admin')),
        body: const EmptyStateWidget(
          icon: Icons.lock_rounded,
          title: 'Not available',
          subtitle: 'This area is restricted to platform administrators.',
        ),
      );
    }

    final all = provider.companies;
    final filtered = all.where((c) {
      if (_statusFilter != null && c.status != _statusFilter) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return c.companyName.toLowerCase().contains(q) ||
          c.id.toLowerCase().contains(q) ||
          c.permanentJoinCode.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.admin_panel_settings_rounded,
          color: AppTheme.infoColor,
          title: 'Super Admin',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _Summary(
              total: all.length,
              active: all.where((c) => c.isActive).length,
              suspended: provider.suspendedCount,
              deleted: provider.deletedCount,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search name, id or join code',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _statusFilter == null,
                    onTap: () => setState(() => _statusFilter = null),
                  ),
                  for (final status in CompanyStatus.values)
                    _FilterChip(
                      label: switch (status) {
                        CompanyStatus.active => 'Active',
                        CompanyStatus.suspended => 'Suspended',
                        CompanyStatus.deleted => 'Deleted',
                      },
                      selected: _statusFilter == status,
                      onTap: () => setState(
                        () => _statusFilter =
                            _statusFilter == status ? null : status,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (provider.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  provider.errorMessage!,
                  style: const TextStyle(color: AppTheme.dangerColor),
                ),
              ),
            Expanded(
              child: provider.isLoading && all.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? EmptyStateWidget(
                      icon: Icons.business_rounded,
                      title: all.isEmpty
                          ? 'No companies yet'
                          : 'Nothing matches',
                      subtitle: all.isEmpty
                          ? 'Workspaces appear here as soon as they are created.'
                          : 'Try a different search or filter.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) =>
                          _CompanyTile(company: filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.total,
    required this.active,
    required this.suspended,
    required this.deleted,
  });

  final int total;
  final int active;
  final int suspended;
  final int deleted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GlassPanel(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _Stat(label: 'Companies', value: total),
              _Stat(label: 'Active', value: active, color: AppTheme.successColor),
              _Stat(
                label: 'Suspended',
                value: suspended,
                color: AppTheme.warningColor,
              ),
              _Stat(label: 'Deleted', value: deleted, color: AppTheme.dangerColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  )),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({required this.company});

  final CompanyModel company;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SuperAdminProvider>();
    final stats = provider.statsFor(company.id);
    if (stats == null) {
      // Loaded lazily so opening the dashboard does not fire an aggregation
      // query for every tenant at once.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => provider.loadStats(company.id),
      );
    }

    final statusColor = switch (company.status) {
      CompanyStatus.active => AppTheme.successColor,
      CompanyStatus.suspended => AppTheme.warningColor,
      CompanyStatus.deleted => AppTheme.dangerColor,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        child: ListTile(
          title: Row(
            children: [
              Flexible(
                child: Text(
                  company.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              _Badge(label: company.plan.label, color: AppTheme.infoColor),
              if (!company.isActive) ...[
                const SizedBox(width: 6),
                _Badge(label: company.statusLabel, color: statusColor),
              ],
            ],
          ),
          subtitle: Text(
            [
              if (stats != null)
                '${stats.users} user(s) • ${stats.products} product(s)'
              else
                'Loading counts…',
              if (company.createdAt != null)
                'Created ${AppDates.day.format(company.createdAt!)}',
            ].join(' • '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.pushNamed(
            context,
            AppRoutes.superAdminCompany,
            arguments: company,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
