import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../config/permissions.dart';
import '../../widgets/permission_gate.dart';
import '../../providers/stock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../models/user_model.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import '../../config/feature_map.dart';
import '../../widgets/tab_context_header.dart';
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
    final perms = context.select<AuthProvider, Map<String, bool>>(
      (a) => a.currentUser?.effectivePermissions ?? UserModel.defaultPermissions,
    );
    final settings = context.watch<SettingsProvider>();
    final billingOn = context.watch<BillingSettingsProvider>().billingEnabled;
    final stockProvider = context.watch<StockProvider>();

    final reportShortcuts = FeatureMap.entriesByCategory(
      FeatureCategory.reports,
      perms,
      billingEnabled: billingOn,
      barcodeEnabled: settings.barcodeEnabled,
      vendorsEnabled: settings.vendorsEnabled,
      pricingEnabled: settings.pricingEnabled,
    );

    final start = stockProvider.filterStartDate;
    final end = stockProvider.filterEndDate;
    final dateLabel = start != null && end != null
        ? '${_dateFormat.format(start)}–${_dateFormat.format(end)}'
        : 'All Time';

    return PermissionGate(
      permission: AppPermissions.viewReports,
      child: Column(
        children: [
          // Status bar gap
          SizedBox(height: MediaQuery.of(context).padding.top),

          CompactTabHeader(
            icon: Icons.analytics_rounded,
            title: 'Reports',
            subtitle: 'Select a tab below or choose a deep report shortcut.',
            shortcuts: reportShortcuts,
            actions: [
              // Date chip — tappable, compact
              GestureDetector(
                onTap: () => _showDateRangeSheet(stockProvider),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 11, color: AppTheme.primaryColor),
                      const SizedBox(width: 4),
                      Text(
                        dateLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, size: 14, color: AppTheme.primaryColor),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Export button
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.ios_share_rounded, size: 20, color: AppTheme.textSec(context)),
                tooltip: 'Export PDF / Excel',
                onPressed: _openExportSheet,
              ),
            ],
          ),

          // ── Compact tab bar ──
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            indicatorSize: TabBarIndicatorSize.label,
            indicatorColor: AppTheme.primaryColor,
            indicatorWeight: 2.5,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textSec(context),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const [
              Tab(text: 'Summary'),
              Tab(text: 'Builder'),
              Tab(text: 'Charts'),
              Tab(text: 'Forecast'),
            ],
          ),
          const Divider(height: 1, thickness: 0.5),

          // ── Tab bodies ──
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
