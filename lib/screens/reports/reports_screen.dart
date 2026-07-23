import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../providers/stock_provider.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import 'tabs/executive_summary_tab.dart';
import 'tabs/custom_report_builder_tab.dart';
import 'tabs/analytics_charts_tab.dart';
import 'tabs/predictive_forecasting_tab.dart';
import 'widgets/reports_export_sheet.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _dateFormat = DateFormat('dd MMM');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showDateRangeSheet(StockProvider stockProvider) {
    showModalBottomSheet(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Select Date Filter',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.today_rounded),
                title: const Text('Today'),
                onTap: () {
                  final now = DateTime.now();
                  stockProvider.setDateRangeFilter(now, now);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.date_range_rounded),
                title: const Text('Last 7 Days'),
                onTap: () {
                  stockProvider.setDateRangeFilter(
                    DateTime.now().subtract(const Duration(days: 7)),
                    DateTime.now(),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_rounded),
                title: const Text('Last 30 Days'),
                onTap: () {
                  stockProvider.setDateRangeFilter(
                    DateTime.now().subtract(const Duration(days: 30)),
                    DateTime.now(),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: const Text('Last 90 Days'),
                onTap: () {
                  stockProvider.setDateRangeFilter(
                    DateTime.now().subtract(const Duration(days: 90)),
                    DateTime.now(),
                  );
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar_rounded),
                title: const Text('Custom Range...'),
                onTap: () async {
                  Navigator.pop(context);
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: stockProvider.filterStartDate != null
                        ? DateTimeRange(
                            start: stockProvider.filterStartDate!,
                            end: stockProvider.filterEndDate ?? DateTime.now(),
                          )
                        : DateTimeRange(
                            start: DateTime.now()
                                .subtract(const Duration(days: 30)),
                            end: DateTime.now(),
                          ),
                  );
                  if (picked != null && mounted) {
                    stockProvider.setDateRangeFilter(
                        picked.start, picked.end);
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.clear_all_rounded),
                title: const Text('All Time'),
                onTap: () {
                  stockProvider.setDateRangeFilter(null, null);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openExportSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const ReportsExportSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: AppPermissions.viewReports,
      // No Scaffold wrapper — we sit inside HomeScreen's Scaffold
      child: Column(
        children: [
          // ── Header bar (replaces AppBar) ────────────────────────────
          _ReportsHeader(
            tabController: _tabController,
            dateFormat: _dateFormat,
            onDateFilter: (sp) => _showDateRangeSheet(sp),
            onExport: _openExportSheet,
          ),

          // ── Tab bodies ───────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ExecutiveSummaryTab(
                  onNavigateTab: (i) => _tabController.animateTo(i),
                ),
                const CustomReportBuilderTab(),
                const AnalyticsChartsTab(),
                const PredictiveForecastingTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ultra-compact header — single bar + slim tab row
// ─────────────────────────────────────────────────────────────────────────────
class _ReportsHeader extends StatelessWidget {
  final TabController tabController;
  final DateFormat dateFormat;
  final void Function(StockProvider) onDateFilter;
  final VoidCallback onExport;

  const _ReportsHeader({
    required this.tabController,
    required this.dateFormat,
    required this.onDateFilter,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Consumer<StockProvider>(
      builder: (context, stockProvider, _) {
        final start = stockProvider.filterStartDate;
        final end = stockProvider.filterEndDate;
        final dateLabel = start != null && end != null
            ? '${dateFormat.format(start)}–${dateFormat.format(end)}'
            : 'All Time';

        return Material(
          color: AppTheme.bg(context),
          elevation: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status bar gap
              SizedBox(height: topPadding),

              // ── Single combined bar ───────────────────────────────────
              SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      // Title
                      Icon(Icons.analytics_rounded,
                          color: AppTheme.primaryColor, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Reports',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Date chip — tappable, compact
                      Flexible(
                        child: GestureDetector(
                          onTap: () => onDateFilter(stockProvider),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today_rounded,
                                    size: 11,
                                    color: AppTheme.primaryColor),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    dateLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                                Icon(Icons.arrow_drop_down,
                                    size: 14,
                                    color: AppTheme.primaryColor),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Export icon button
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.ios_share_rounded,
                              size: 20,
                              color: AppTheme.textSec(context)),
                          tooltip: 'Export PDF / Excel',
                          onPressed: onExport,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Compact tab bar (text only, no stacked icons) ─────────
              TabBar(
                controller: tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                labelPadding:
                    const EdgeInsets.symmetric(horizontal: 12),
                indicatorSize: TabBarIndicatorSize.label,
                indicatorColor: AppTheme.primaryColor,
                indicatorWeight: 2.5,
                labelColor: AppTheme.primaryColor,
                unselectedLabelColor: AppTheme.textSec(context),
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle:
                    const TextStyle(fontSize: 13),
                tabs: const [
                  Tab(text: 'Summary'),
                  Tab(text: 'Builder'),
                  Tab(text: 'Charts'),
                  Tab(text: 'Forecast'),
                ],
              ),
              const Divider(height: 1, thickness: 0.5),
            ],
          ),
        );
      },
    );
  }
}
