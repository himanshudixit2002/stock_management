import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../config/theme.dart';
import '../../providers/audit_log_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/audit_log_model.dart';
import '../../utils/responsive.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  String _selectedEntity = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int _visibleCount = 50;

  static const _entityFilters = [
    'All',
    'Product',
    'Category',
    'Vendor',
    'Order',
    'Stock',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      setState(() => _visibleCount += 30);
    }
  }

  List<AuditLogModel> _filteredLogs(List<AuditLogModel> all) {
    Iterable<AuditLogModel> result = all;

    if (_selectedEntity != 'All') {
      final filter = _selectedEntity.toLowerCase();
      result = result.where((l) => l.entityType.toLowerCase() == filter);
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where(
        (l) =>
            l.entityName.toLowerCase().contains(q) ||
            l.action.toLowerCase().contains(q) ||
            l.userName.toLowerCase().contains(q),
      );
    }

    return result.take(_visibleCount).toList();
  }

  IconData _actionIcon(String action) {
    final a = action.toLowerCase();
    if (a.contains('create') || a.contains('add'))
      return Icons.add_circle_rounded;
    if (a.contains('update') || a.contains('edit')) return Icons.edit_rounded;
    if (a.contains('delete') || a.contains('remove'))
      return Icons.delete_rounded;
    if (a.contains('stock_in') || a.contains('receive'))
      return Icons.archive_rounded;
    if (a.contains('stock_out') || a.contains('dispatch'))
      return Icons.unarchive_rounded;
    if (a.contains('transfer')) return Icons.swap_horiz_rounded;
    if (a.contains('damage')) return Icons.report_problem_rounded;
    return Icons.history_rounded;
  }

  Color _actionColor(String action) {
    final a = action.toLowerCase();
    if (a.contains('create') || a.contains('add')) return AppTheme.successColor;
    if (a.contains('delete') || a.contains('remove'))
      return AppTheme.dangerColor;
    if (a.contains('damage')) return AppTheme.dangerColor;
    if (a.contains('update') || a.contains('edit')) return AppTheme.infoColor;
    if (a.contains('transfer')) return AppTheme.indigoColor;
    return AppTheme.primaryColor;
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewAuditLog,
      featureName: 'Audit Log',
      child: Builder(builder: _buildContent),
    );
  }

  Widget _buildContent(BuildContext context) {

    final provider = context.watch<AuditLogProvider>();
    final logs = _filteredLogs(provider.logs);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        title: const AppBarTitleRow(
          icon: Icons.history_edu_rounded,
          color: AppTheme.indigoColor,
          title: 'Audit Log',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  Responsive.horizontalPadding(context),
                  8,
                  Responsive.horizontalPadding(context),
                  4,
                ),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by name, action, or user...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textTer(context),
                      ),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _visibleCount = 50;
                                });
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppTheme.dividerC(context),
                        ),
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => setState(() {
                      _searchQuery = v;
                      _visibleCount = 50;
                    }),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                    horizontal: Responsive.horizontalPadding(context),
                    vertical: 4,
                  ),
                  itemCount: _entityFilters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final filter = _entityFilters[i];
                    final selected = _selectedEntity == filter;
                    return _FilterChip(
                      label: filter,
                      selected: selected,
                      onTap: () => setState(() {
                        _selectedEntity = filter;
                        _visibleCount = 50;
                      }),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: provider.isLoading
                    ? const ShimmerLoading(layout: ShimmerLayout.listTile)
                    : logs.isEmpty
                    ? const EmptyStateWidget(
                        icon: Icons.history_rounded,
                        title: 'No Activity',
                        subtitle: 'No audit log entries match your filters.',
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          final companyId = context
                              .read<AuthProvider>()
                              .currentUser!
                              .companyId;
                          context.read<AuditLogProvider>().initialize(
                            companyId: companyId,
                          );
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.symmetric(
                            horizontal: Responsive.horizontalPadding(context),
                            vertical: 8,
                          ),
                          itemCount: logs.length,
                          itemBuilder: (_, i) => _AuditLogTile(
                            log: logs[i],
                            icon: _actionIcon(logs[i].action),
                            color: _actionColor(logs[i].action),
                            relativeTime: _relativeTime(logs[i].timestamp),
                            isLast: i == logs.length - 1,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditLogTile extends StatefulWidget {
  final AuditLogModel log;
  final IconData icon;
  final Color color;
  final String relativeTime;
  final bool isLast;

  const _AuditLogTile({
    required this.log,
    required this.icon,
    required this.color,
    required this.relativeTime,
    required this.isLast,
  });

  @override
  State<_AuditLogTile> createState() => _AuditLogTileState();
}

class _AuditLogTileState extends State<_AuditLogTile> {
  bool _expanded = false;

  String _buildDescription() {
    final l = widget.log;
    final user = l.userName.isNotEmpty ? l.userName : 'System';
    final entity = l.entityName.isNotEmpty ? "'${l.entityName}'" : '';
    final type = l.entityType.isNotEmpty ? l.entityType : 'item';
    return '$user ${l.action} $type $entity'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final hasChanges = log.changes.isNotEmpty;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 14),
                ),
                if (!widget.isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppTheme.dividerC(context),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GlassCard(
                borderRadius: 12,
                onTap: hasChanges
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _buildDescription(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (log.entityType.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: widget.color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                log.entityType,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: widget.color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            widget.relativeTime,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSec(context),
                            ),
                          ),
                          if (hasChanges) ...[
                            const Spacer(),
                            Icon(
                              _expanded ? Icons.expand_less : Icons.expand_more,
                              size: 16,
                              color: AppTheme.textSec(context),
                            ),
                          ],
                        ],
                      ),
                      if (_expanded && hasChanges) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        ...log.changes.entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    e.key,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textSec(context),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '${e.value}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textPri(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.indigoColor
                : AppTheme.indigoColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.indigoColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
