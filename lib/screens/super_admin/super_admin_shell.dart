import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/super_admin_provider.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/empty_state_widget.dart';
import 'sections/global_users_section.dart';
import 'sections/health_section.dart';
import 'sections/overview_section.dart';
import 'sections/plans_section.dart';
import 'sections/platform_audit_section.dart';
import 'sections/workspaces_section.dart';

/// One destination in the console.
enum ConsolePage {
  overview('Overview', Icons.insights_rounded),
  workspaces('Workspaces', Icons.business_rounded),
  users('Users', Icons.people_alt_rounded),
  plans('Plans', Icons.workspace_premium_rounded),
  audit('Audit', Icons.history_rounded),
  health('Health', Icons.health_and_safety_rounded);

  const ConsolePage(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The platform console.
///
/// A super admin gets this instead of the whole app (see `app.dart`), so it has
/// to stand on its own — hence a navigation shell rather than the two-tab bar
/// this replaced. Wide layouts get a rail, narrow ones a bottom bar, following
/// the same split the tenant home screen uses.
class SuperAdminShell extends StatefulWidget {
  const SuperAdminShell({super.key});

  @override
  State<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends State<SuperAdminShell> {
  ConsolePage _page = ConsolePage.overview;
  bool _requestedAllStats = false;
  bool _refreshingStats = false;

  /// Captured while the element is still active.
  ///
  /// `dispose()` must not reach for an inherited widget: `unmount()` marks the
  /// element defunct *before* calling it, so `context.read` throws there — and
  /// a `mounted` guard does not help, because `_element` is only nulled after
  /// `dispose()` returns. Holding the reference is the only way the listener
  /// actually gets removed.
  SuperAdminProvider? _provider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<SuperAdminProvider>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<SuperAdminProvider>();
      provider.startWatching();
      provider.addListener(_loadAllStatsOnce);
    });
  }

  /// Counts for the whole estate, once the company list has arrived.
  ///
  /// The hero totals sum whatever has loaded, so leaving this to lazy per-tile
  /// loading meant the headline numbers only counted the workspaces someone had
  /// scrolled past.
  void _loadAllStatsOnce() {
    if (_requestedAllStats || !mounted) return;
    final provider = context.read<SuperAdminProvider>();
    if (provider.companies.isEmpty) return;
    _requestedAllStats = true;
    provider.loadAllStats();
  }

  @override
  void dispose() {
    _provider?.removeListener(_loadAllStatsOnce);
    super.dispose();
  }

  /// Re-reads every workspace's counts.
  ///
  /// [SuperAdminProvider.loadAllStats] skips anything already cached, so the
  /// refresh button on top of it did nothing at all after the first load.
  Future<void> _refreshStats() async {
    if (_refreshingStats) return;
    setState(() => _refreshingStats = true);
    _requestedAllStats = true;
    try {
      await context.read<SuperAdminProvider>().reloadAllStats();
    } finally {
      if (mounted) setState(() => _refreshingStats = false);
    }
  }

  void _select(ConsolePage page) {
    if (page == _page) return;
    setState(() => _page = page);
    final provider = context.read<SuperAdminProvider>();
    // Cross-tenant streams are opened only when their page is first entered.
    switch (page) {
      case ConsolePage.users:
        provider.startWatchingGlobalUsers();
      case ConsolePage.audit:
        provider.startWatchingPlatformAudit();
      case ConsolePage.health:
        provider.startWatchingGlobalUsers();
      case _:
        break;
    }
  }

  Widget _body() => switch (_page) {
    ConsolePage.overview => OverviewSection(onOpenWorkspaces: () => _select(ConsolePage.workspaces)),
    ConsolePage.workspaces => const WorkspacesSection(),
    ConsolePage.users => const GlobalUsersSection(),
    ConsolePage.plans => const PlansSection(),
    ConsolePage.audit => const PlatformAuditSection(),
    ConsolePage.health => const HealthSection(),
  };

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

    final wide = Responsive.isWide(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: AppBarTitleRow(
          icon: Icons.admin_panel_settings_rounded,
          color: AppTheme.infoColor,
          title: 'Platform Console',
          subtitle: _page.label,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh counts',
            icon: _refreshingStats
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _refreshingStats ? null : _refreshStats,
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              final confirmed = await showConfirmDialog(
                context,
                title: 'Sign out?',
                message: 'You will be returned to the login screen.',
                confirmLabel: 'Sign out',
                icon: Icons.logout_rounded,
              );
              if (!confirmed || !context.mounted) return;
              await context.read<AuthProvider>().logout();
            },
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                _ConsoleRail(selected: _page, onSelect: _select),
                VerticalDivider(
                  width: 1,
                  color: AppTheme.dividerC(context),
                ),
                Expanded(child: _body()),
              ],
            )
          : _body(),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page.index,
              onDestinationSelected: (i) => _select(ConsolePage.values[i]),
              // Six destinations is one past what Material 3 sizes for, and at
              // 360dp each label gets ~60px where "Workspaces" needs ~68. Only
              // labelling the selected one keeps the rest legible instead of
              // clipping every label.
              labelBehavior:
                  MediaQuery.sizeOf(context).width < 420
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final page in ConsolePage.values)
                  NavigationDestination(
                    icon: Icon(page.icon),
                    label: page.label,
                    tooltip: page.label,
                  ),
              ],
            ),
    );
  }
}

class _ConsoleRail extends StatelessWidget {
  const _ConsoleRail({required this.selected, required this.onSelect});

  final ConsolePage selected;
  final ValueChanged<ConsolePage> onSelect;

  /// Roughly what one labelled destination occupies, used only to decide
  /// whether all six will fit before the rail lays itself out.
  static const double _labelledDestinationHeight = 72;

  @override
  Widget build(BuildContext context) {
    // A NavigationRail lays its destinations out in a Column that does not
    // scroll, and Responsive.isWide is true for a landscape phone — roughly
    // 330px of body height against the ~450px six labelled destinations need.
    // Unfixed, the rail overflowed and Audit and Health became unreachable.
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitsLabelled =
            constraints.maxHeight >=
            ConsolePage.values.length * _labelledDestinationHeight;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: NavigationRail(
                selectedIndex: selected.index,
                onDestinationSelected: (i) => onSelect(ConsolePage.values[i]),
                labelType: fitsLabelled
                    ? NavigationRailLabelType.all
                    : NavigationRailLabelType.selected,
                backgroundColor: AppTheme.surface(context),
                selectedIconTheme: const IconThemeData(
                  color: AppTheme.infoColor,
                ),
                selectedLabelTextStyle: const TextStyle(
                  color: AppTheme.infoColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                unselectedLabelTextStyle: TextStyle(
                  color: AppTheme.textSec(context),
                  fontSize: 12,
                ),
                destinations: [
                  for (final page in ConsolePage.values)
                    NavigationRailDestination(
                      icon: Tooltip(
                        message: page.label,
                        child: Icon(page.icon),
                      ),
                      label: Text(page.label),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
