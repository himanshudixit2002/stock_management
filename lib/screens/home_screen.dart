import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/stock_provider.dart';
import '../providers/billing_settings_provider.dart';
import '../providers/settings_provider.dart';
import '../config/feature_map.dart';
import '../config/theme.dart';
import '../config/motion.dart';
import '../models/user_model.dart';
import '../utils/responsive.dart';
import '../utils/dialogs.dart';
import '../widgets/feature_tour.dart';
import '../widgets/keyboard_shortcuts_scope.dart';
import 'home/home_tab.dart';
import 'products/product_list_screen.dart';
import 'reports/reports_tab.dart';
import 'ai/rag_chat_screen.dart';
import 'settings/settings_screen.dart';
import '../widgets/animations.dart';
import '../widgets/floating_bottom_nav.dart';
import '../widgets/offline_banner.dart';
import 'package:flutter_animate/flutter_animate.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Key used by [AuthWrapper] so browser/system back can unwind tabs on the
  /// shell route instead of popping the logged-in route off the stack.
  static final GlobalKey<HomeScreenState> shellKey =
      GlobalKey<HomeScreenState>();

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  DateTime? _lastBackPress;
  bool _showTour = false;

  // Visited-tab stack so the back gesture/button returns to the previously
  // viewed tab (natural in-app navigation) instead of jumping straight out.
  final List<int> _tabHistory = [];

  // Tabs that have been visited at least once. Bodies are built lazily on
  // first visit, then kept mounted by the IndexedStack so their state/scroll
  // position is preserved. Unvisited tabs render a zero-cost placeholder and
  // therefore never build their widget tree or touch Firestore until opened.
  // Keyed by tab *kind* so the set stays correct even if permissions change
  // the tab list/indices.
  final Set<FloatingNavTabKind> _mountedTabs = {FloatingNavTabKind.home};

  // Drives a gentle fade + rise when switching tabs. The IndexedStack keeps its
  // identity (so each tab's state/scroll position is preserved) while this
  // controller animates only the opacity/offset for a soft, cloudy settle.
  late final AnimationController _tabController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _tabFade = CurvedAnimation(
    parent: _tabController,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _tabSlide = Tween<Offset>(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _tabController, curve: Curves.easeOutCubic));

  void _playTabTransition() {
    if (reduceMotion(context)) {
      _tabController.value = 1.0;
      return;
    }
    _tabController.forward(from: 0.55);
  }

  Widget _tabTransition(Widget child) => FadeTransition(
    opacity: _tabFade,
    child: SlideTransition(position: _tabSlide, child: child),
  );

  void switchToTab(int index) {
    if (index == _currentIndex) return;
    _tabHistory.add(_currentIndex);
    setState(() => _currentIndex = index);
    _playTabTransition();
    _loadAnalyticsIfNeeded(index);
  }

  void _loadAnalyticsIfNeeded(int index) {
    final perms =
        context.read<AuthProvider>().currentUser?.effectivePermissions ??
        UserModel.defaultPermissions;
    final reportsIndex = perms['canViewReports'] == true
        ? (perms['canViewProducts'] == true ? 2 : 1)
        : -1;
    if (index == 0 || index == reportsIndex) {
      context.read<ProductProvider>().loadAnalytics();
    }
  }

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;
    _tabHistory.add(_currentIndex);
    setState(() => _currentIndex = index);
    _playTabTransition();
    _loadAnalyticsIfNeeded(index);
  }

  /// Handles browser/system back when the app shell is the top route (no pushed
  /// sub-page). Unwinds tab history (e.g. Products → Home), then stays on web.
  void handleShellBack() {
    if (_tabHistory.isNotEmpty) {
      final previous = _tabHistory.removeLast();
      setState(() => _currentIndex = previous);
      _playTabTransition();
      _loadAnalyticsIfNeeded(previous);
      return;
    }
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      _playTabTransition();
      _loadAnalyticsIfNeeded(0);
      return;
    }
    // At the root Home tab with no history to unwind.
    if (kIsWeb) return; // Stay on the page; do not leave the website.
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    showInfoSnackBar(context, 'Press back again to exit');
  }

  Future<void> _checkFeatureTour() async {
    final completed = await FeatureTour.isCompleted();
    if (!completed && mounted) {
      setState(() => _showTour = true);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAnalyticsIfNeeded(0);
      _checkFeatureTour();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Opens the categorized Quick Actions sheet, merged from the floating nav's
  /// raised centre button. Built from [FeatureMap] homePrimary entries so no
  /// daily-operation route is lost. Routes/permissions are unchanged.
  void _openQuickActionsSheet(List<FeatureEntry> entries) {
    if (entries.isEmpty) return;
    // Group by category so the sheet reads as a clear catalog.
    final grouped = <FeatureCategory, List<FeatureEntry>>{};
    for (final e in entries) {
      grouped.putIfAbsent(e.category, () => []).add(e);
    }

    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SlideUpSheet(
        title: 'Quick Actions',
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                for (final entry in grouped.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Text(
                      FeatureMap.categoryMeta[entry.key]?.title ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: AppTheme.textTer(ctx),
                      ),
                    ),
                  ),
                  ...entry.value.map(
                    (feature) => _QuickActionTile(
                      feature: feature,
                      color: FeatureMap.categoryColor(feature.category),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, feature.route);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isWide(context);

    final perms = context.select<AuthProvider, Map<String, bool>>(
      (a) =>
          a.currentUser?.effectivePermissions ?? UserModel.defaultPermissions,
    );
    final settings = context.watch<SettingsProvider>();
    final billingOn = context.watch<BillingSettingsProvider>().billingEnabled;

    final quickActions = FeatureMap.visibleEntriesFor(
      FeaturePlacement.homePrimary,
      perms,
      billingEnabled: billingOn,
      barcodeEnabled: settings.barcodeEnabled,
      vendorsEnabled: settings.vendorsEnabled,
      pricingEnabled: settings.pricingEnabled,
    );

    final tabs = <_ShellTab>[
      _ShellTab(
        Icons.home_rounded,
        Icons.home_outlined,
        'Home',
        FloatingNavTabKind.home,
        (_) => const HomeTab(),
      ),
      if (perms['canViewProducts'] == true)
        _ShellTab(
          Icons.inventory_2_rounded,
          Icons.inventory_2_outlined,
          'Products',
          FloatingNavTabKind.products,
          (_) => const ProductListScreen(),
        ),
      if (perms['canViewReports'] == true)
        _ShellTab(
          Icons.analytics_rounded,
          Icons.analytics_outlined,
          'Reports',
          FloatingNavTabKind.reports,
          (_) => const ReportsTab(),
        ),

      _ShellTab(
        Icons.settings_rounded,
        Icons.settings_outlined,
        'Settings',
        FloatingNavTabKind.settings,
        (_) => const SettingsScreen(),
      ),
    ];

    final safeIndex = _currentIndex.clamp(0, tabs.length - 1);
    // Mount the active tab on demand (idempotent); previously visited tabs stay
    // in [_mountedTabs] so the IndexedStack keeps their state alive.
    _mountedTabs.add(tabs[safeIndex].kind);

    Widget scaffold;

    if (isWide) {
      scaffold = Scaffold(
        backgroundColor: AppTheme.bg(context),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: Row(
            children: [
              _buildNavigationRail(context, tabs, safeIndex, quickActions),
              Expanded(
                child: _tabTransition(
                  IndexedStack(
                    index: safeIndex,
                    children: _buildTabBodies(tabs),
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _buildAskAIFab(context, isWide: true),
      );
    } else {
      scaffold = Scaffold(
        backgroundColor: AppTheme.bg(context),
        // No Scaffold.bottomNavigationBar — the floating pill is overlaid so
        // body content scrolls behind it.
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: Stack(
            children: [
              Positioned.fill(
                child: _tabTransition(
                  IndexedStack(
                    index: safeIndex,
                    children: _buildTabBodies(tabs),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: FloatingBottomNav(
                  currentIndex: safeIndex,
                  tabs: tabs.map((t) => t.toNavTab()).toList(),
                  onTap: _onTabSelected,
                ),
              ),
              Positioned(
                right: 16,
                bottom: 100, // Float above bottom nav
                child: _buildAskAIFab(context, isWide: false),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = AppTheme.isDark(context);
    return KeyboardShortcutsScope(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        // Transparent so the floating pill shows over content; the body
        // gradient fills the gesture-nav area beneath it.
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: Stack(
              children: [
                scaffold,
                if (_showTour)
                  FeatureTour(
                    onComplete: () => setState(() => _showTour = false),
                  ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// Builds the IndexedStack children, mounting a tab's real body only once it
  /// has been visited and a lightweight placeholder otherwise. Visited bodies
  /// keep a stable key so the IndexedStack preserves their element/state when
  /// switching tabs (instant, <100ms-feel switching with no rebuild cost).
  List<Widget> _buildTabBodies(List<_ShellTab> tabs) {
    return [
      for (final t in tabs)
        if (_mountedTabs.contains(t.kind))
          KeyedSubtree(
            key: ValueKey<FloatingNavTabKind>(t.kind),
            child: Builder(builder: t.builder),
          )
        else
          const SizedBox.shrink(),
    ];
  }

  // ---------------------------------------------------------------------------
  // Wide screens: upgraded glass NavigationRail with badges + quick actions.
  // ---------------------------------------------------------------------------
  Widget _buildNavigationRail(
    BuildContext context,
    List<_ShellTab> tabs,
    int safeIndex,
    List<FeatureEntry> quickActions,
  ) {
    final outOfStock = context.select<ProductProvider, int>(
      (p) => p.outOfStockCount,
    );
    final lowStock = context.select<ProductProvider, int>(
      (p) => p.lowStockCount,
    );
    final todayTxns = context.select<StockProvider, int>((s) {
      final now = DateTime.now();
      return s.allTransactions
          .where(
            (t) =>
                t.date.year == now.year &&
                t.date.month == now.month &&
                t.date.day == now.day,
          )
          .length;
    });

    Widget railIcon(_ShellTab t, IconData icon) {
      switch (t.kind) {
        case FloatingNavTabKind.products:
          if (outOfStock > 0) {
            return Badge(
              label: Text(outOfStock > 99 ? '99+' : '$outOfStock'),
              backgroundColor: AppTheme.dangerColor,
              child: Icon(icon),
            );
          }
          if (lowStock > 0) {
            return Badge(
              label: Text(lowStock > 99 ? '99+' : '$lowStock'),
              backgroundColor: AppTheme.warningColor,
              child: Icon(icon),
            );
          }
          return Icon(icon);
        case FloatingNavTabKind.reports:
          return Badge(
            isLabelVisible: todayTxns > 0,
            backgroundColor: AppTheme.infoColor,
            child: Icon(icon),
          );
        case FloatingNavTabKind.home:
        case FloatingNavTabKind.ai:
        case FloatingNavTabKind.settings:
          return Icon(icon);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.glassContent(context),
        border: Border(
          right: BorderSide(color: AppTheme.glassBorderCont(context), width: 1),
        ),
        boxShadow: AppTheme.isDark(context) ? null : AppTheme.softShadow,
      ),
      child: NavigationRail(
        selectedIndex: safeIndex,
        onDestinationSelected: _onTabSelected,
        labelType: NavigationRailLabelType.all,
        minWidth: 80,
        backgroundColor: Colors.transparent,
        indicatorColor: AppTheme.primaryColor.withValues(alpha: 0.12),
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: const IconThemeData(
          color: AppTheme.primaryColor,
          size: 26,
        ),
        unselectedIconTheme: IconThemeData(
          color: AppTheme.iconMute(context),
          size: 24,
        ),
        selectedLabelTextStyle: const TextStyle(
          color: AppTheme.primaryColor,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: AppTheme.iconMute(context),
          fontSize: 12,
        ),
        leading: Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Column(
            children: [
              Image.asset('logo.png', width: 38, height: 38),
              const SizedBox(height: 6),
              Container(
                width: 32,
                height: 2,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
        trailing: quickActions.isNotEmpty
            ? Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _RailQuickActionsButton(
                      onTap: () => _openQuickActionsSheet(quickActions),
                    ),
                  ),
                ),
              )
            : null,
        destinations: tabs
            .map(
              (t) => NavigationRailDestination(
                icon: Tooltip(
                  message: t.label,
                  child: railIcon(t, t.inactiveIcon),
                ),
                selectedIcon: Tooltip(
                  message: t.label,
                  child: railIcon(t, t.icon),
                ),
                label: Text(t.label),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildAskAIFab(BuildContext context, {required bool isWide}) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        shape: isWide ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: isWide ? BorderRadius.circular(24) : null,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: isWide ? BorderRadius.circular(24) : BorderRadius.circular(30),
        child: InkWell(
          borderRadius: isWide ? BorderRadius.circular(24) : BorderRadius.circular(30),
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const RagChatScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.05),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                      child: child,
                    ),
                  );
                },
              ),
            );
          },
          child: Padding(
            padding: isWide ? const EdgeInsets.symmetric(horizontal: 20, vertical: 14) : const EdgeInsets.all(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
                if (isWide) ...[
                  const SizedBox(width: 10),
                  const Text(
                    'Ask AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 0.3,
                    ),
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    ).animate().scale(delay: 500.ms, duration: 500.ms, curve: Curves.easeOutBack);
  }
}

/// Internal description of a shell tab (lazy body builder + nav metadata).
class _ShellTab {
  final IconData icon;
  final IconData inactiveIcon;
  final String label;
  final FloatingNavTabKind kind;

  /// Built lazily on first visit so unvisited tabs cost nothing.
  final WidgetBuilder builder;

  const _ShellTab(
    this.icon,
    this.inactiveIcon,
    this.label,
    this.kind,
    this.builder,
  );

  FloatingNavTab toNavTab() => FloatingNavTab(
    icon: icon,
    inactiveIcon: inactiveIcon,
    label: label,
    kind: kind,
  );
}

/// A compact "Quick Actions" button docked at the bottom of the rail.
class _RailQuickActionsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RailQuickActionsButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Quick actions',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Actions',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSec(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single row in the categorized Quick Actions sheet.
class _QuickActionTile extends StatelessWidget {
  final FeatureEntry feature;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionTile({
    super.key,
    required this.feature,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(feature.icon, color: color, size: 22),
      ),
      title: Text(
        feature.label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppTheme.textPri(context),
        ),
      ),
      subtitle: Text(
        feature.subtitle,
        style: TextStyle(fontSize: 12, color: AppTheme.textTer(context)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
