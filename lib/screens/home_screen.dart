import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/stock_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/home_customization_provider.dart';
import '../providers/billing_settings_provider.dart';
import '../providers/settings_provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/user_model.dart';
import '../models/stock_transaction_model.dart';
import '../utils/responsive.dart';
import '../utils/dialogs.dart';
import '../widgets/feature_tour.dart';
import 'products/product_list_screen.dart';
import 'reports/reports_screen.dart';
import 'settings/settings_screen.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/glass_panel.dart';
import '../widgets/offline_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  DateTime? _lastBackPress;
  bool _showTour = false;

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

  void _playTabTransition() => _tabController.forward(from: 0.55);

  Widget _tabTransition(Widget child) => FadeTransition(
    opacity: _tabFade,
    child: SlideTransition(position: _tabSlide, child: child),
  );

  void switchToTab(int index) {
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
    setState(() => _currentIndex = index);
    _playTabTransition();
    _loadAnalyticsIfNeeded(index);
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

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isWide(context);

    final perms = context.select<AuthProvider, Map<String, bool>>(
      (a) =>
          a.currentUser?.effectivePermissions ?? UserModel.defaultPermissions,
    );

    final tabs = <_TabItem>[
      _TabItem(
        Icons.home_rounded,
        Icons.home_outlined,
        'Home',
        const _HomeTab(),
      ),
      if (perms['canViewProducts'] == true)
        _TabItem(
          Icons.inventory_2_rounded,
          Icons.inventory_2_outlined,
          'Products',
          const ProductListScreen(),
        ),
      if (perms['canViewReports'] == true)
        _TabItem(
          Icons.analytics_rounded,
          Icons.analytics_outlined,
          'Reports',
          const ReportsScreen(),
        ),
      _TabItem(
        Icons.settings_rounded,
        Icons.settings_outlined,
        'Settings',
        const SettingsScreen(),
      ),
    ];

    final safeIndex = _currentIndex.clamp(0, tabs.length - 1);

    Widget scaffold;

    if (isWide) {
      scaffold = Scaffold(
        backgroundColor: AppTheme.bg(context),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface(context),
                  border: Border(
                    right: BorderSide(
                      color: AppTheme.dividerC(context),
                      width: 1,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: NavigationRail(
                  selectedIndex: safeIndex,
                  onDestinationSelected: (i) => _onTabSelected(i),
                  labelType: NavigationRailLabelType.all,
                  minWidth: 80,
                  backgroundColor: Colors.transparent,
                  indicatorColor: AppTheme.primaryColor.withValues(alpha: 0.1),
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
                  destinations: tabs
                      .map(
                        (t) => NavigationRailDestination(
                          icon: Icon(t.inactiveIcon),
                          selectedIcon: Icon(t.icon),
                          label: Text(t.label),
                        ),
                      )
                      .toList(),
                ),
              ),
              Expanded(
                child: _tabTransition(
                  IndexedStack(
                    index: safeIndex,
                    children: tabs.map((t) => t.body).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      scaffold = Scaffold(
        backgroundColor: AppTheme.bg(context),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: _tabTransition(
            IndexedStack(
              index: safeIndex,
              children: tabs.map((t) => t.body).toList(),
            ),
          ),
        ),
        bottomNavigationBar: _CustomBottomNav(
          currentIndex: safeIndex,
          tabs: tabs,
          onTap: (i) => _onTabSelected(i),
        ),
      );
    }

    final isDark = AppTheme.isDark(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: AppTheme.surface(context),
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (_currentIndex != 0) {
                  setState(() => _currentIndex = 0);
                  return;
                }
                final now = DateTime.now();
                if (_lastBackPress != null &&
                    now.difference(_lastBackPress!) <
                        const Duration(seconds: 2)) {
                  SystemNavigator.pop();
                  return;
                }
                _lastBackPress = now;
                showInfoSnackBar(context, 'Press back again to exit');
              },
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
          ),
        ],
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData inactiveIcon;
  final String label;
  final Widget body;
  const _TabItem(this.icon, this.inactiveIcon, this.label, this.body);
}

class _CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<_TabItem> tabs;
  final ValueChanged<int> onTap;

  const _CustomBottomNav({
    required this.currentIndex,
    required this.tabs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTheme.dividerC(context), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final isSelected = i == currentIndex;
              final tab = tabs[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap(i);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            horizontal: isSelected ? 16 : 12,
                            vertical: isSelected ? 6 : 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryColor.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isSelected ? tab.icon : tab.inactiveIcon,
                            color: isSelected
                                ? AppTheme.primaryColor
                                : AppTheme.textTer(context),
                            size: isSelected ? 24 : 22,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? AppTheme.primaryColor
                                : AppTheme.textTer(context),
                          ),
                          child: Text(tab.label),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home Tab
// ---------------------------------------------------------------------------
class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  void _showQuickActionsSheet(
    BuildContext context,
    List<_SpeedDialItem> items,
  ) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      backgroundColor: Colors.transparent,
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 300),
      ),
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.textSec(ctx).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Quick actions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSec(ctx),
                ),
              ),
              const SizedBox(height: 8),
              ...items.map(
                (item) => ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, color: item.color, size: 22),
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPri(ctx),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, item.route);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final perms = user.effectivePermissions;
    final isWide = Responsive.isWide(context);

    final initials = user.name.trim().isNotEmpty
        ? user.name
              .trim()
              .split(' ')
              .where((w) => w.isNotEmpty)
              .map((w) => w[0])
              .take(2)
              .join()
              .toUpperCase()
        : '?';

    final speedDialItems = <_SpeedDialItem>[
      if (perms['canStockIn'] == true)
        _SpeedDialItem(
          Icons.add_circle_rounded,
          'Stock In',
          AppTheme.successColor,
          AppRoutes.stockIn,
        ),
      if (perms['canStockOut'] == true)
        _SpeedDialItem(
          Icons.remove_circle_rounded,
          'Stock Out',
          AppTheme.primaryColor,
          AppRoutes.stockOut,
        ),
      if (perms['canTransfer'] == true)
        _SpeedDialItem(
          Icons.swap_horiz_rounded,
          'Transfer',
          AppTheme.indigoColor,
          AppRoutes.stockTransfer,
        ),
      if (perms['canDamage'] == true)
        _SpeedDialItem(
          Icons.broken_image_rounded,
          'Damage',
          AppTheme.dangerColor,
          AppRoutes.damageReport,
        ),
      if (perms['canAdjustStock'] == true)
        _SpeedDialItem(
          Icons.tune_rounded,
          'Adjust',
          AppTheme.warningColor,
          AppRoutes.stockAdjustment,
        ),
      if (perms['canHoldStock'] == true)
        _SpeedDialItem(
          Icons.pause_circle_rounded,
          'Hold Stock',
          AppTheme.warningColor,
          AppRoutes.stockHold,
        ),
      if (perms['canReleaseStock'] == true)
        _SpeedDialItem(
          Icons.play_circle_rounded,
          'Release Hold',
          AppTheme.successColor,
          AppRoutes.stockRelease,
        ),
      if (perms['canUseFastPos'] == true &&
          context.watch<BillingSettingsProvider>().billingEnabled)
        _SpeedDialItem(
          Icons.point_of_sale_rounded,
          'Fast POS',
          AppTheme.successColor,
          AppRoutes.fastPos,
        ),
    ];

    return SafeArea(
      child: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: Responsive.contentMaxWidth(context),
              ),
              child: RefreshIndicator(
                onRefresh: () async {
                  final pp = context.read<ProductProvider>();
                  pp.invalidateAnalytics();
                  await pp.loadAnalytics();
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    Responsive.horizontalPadding(context),
                    12,
                    Responsive.horizontalPadding(context),
                    24,
                  ),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.inputBorder(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => Navigator.pushNamed(
                                context,
                                AppRoutes.globalSearch,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search_rounded,
                                    size: 22,
                                    color: AppTheme.textSec(context),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Search products, vendors, barcodes…',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: AppTheme.textSec(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Consumer<NotificationProvider>(
                            builder: (context, notifProvider, _) {
                              final unread = notifProvider.unreadCount;
                              return IconButton(
                                icon: Badge(
                                  isLabelVisible: unread > 0,
                                  label: Text(
                                    unread > 99 ? '99+' : '$unread',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.notifications_outlined,
                                    color: AppTheme.textSec(context),
                                  ),
                                ),
                                tooltip: 'Notifications',
                                onPressed: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.notifications,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Selector<ProductProvider, DateTime?>(
                      selector: (_, p) => p.analyticsFetchedAt,
                      builder: (context, fetchedAt, _) {
                        if (fetchedAt == null) return const SizedBox.shrink();
                        final ago = DateTime.now().difference(fetchedAt);
                        String label;
                        if (ago.inSeconds < 60) {
                          label = 'Updated just now';
                        } else if (ago.inMinutes < 60) {
                          label = 'Updated ${ago.inMinutes}m ago';
                        } else {
                          label =
                              'Updated ${DateFormat.jm().format(fetchedAt)}';
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 2),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textTer(context),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 4),

                    // Profile bar
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: AppTheme.heroGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppTheme.coloredShadow(
                          AppTheme.primaryColor,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2.5,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.15,
                              ),
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _greeting(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  user.name,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                if (user.companyName.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => Navigator.pushNamed(
                                      context,
                                      AppRoutes.companySwitcher,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            user.companyName,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white.withValues(
                                                alpha: 0.95,
                                              ),
                                            ),
                                          ),
                                          if (user.companyMemberships.length >
                                              1) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.swap_horiz_rounded,
                                              size: 16,
                                              color: Colors.white.withValues(
                                                alpha: 0.7,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Text(
                              user.isAdmin ? 'ADMIN' : 'STAFF',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Action buttons
                    if (isWide)
                      _wideActionButtons(context, perms)
                    else
                      _narrowActionButtons(context, perms),

                    const SizedBox(height: 16),

                    _QuickStats(),

                    const SizedBox(height: 16),
                    const _InsightsCard(),

                    const SizedBox(height: 16),
                    const _FavoritesSection(),

                    const SizedBox(height: 16),
                    const _TipOfTheDay(),

                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _QuickLink(
                        icon: Icons.dashboard_rounded,
                        label: 'View Dashboard',
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.dashboard),
                      ),
                    ),

                    if (perms['canDamage'] == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _QuickLink(
                          icon: Icons.report_problem_rounded,
                          label: 'Damage Report',
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.damageHistory,
                          ),
                        ),
                      ),

                    if (perms['canImport'] == true)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _QuickLink(
                          icon: Icons.sync_rounded,
                          label: 'Update from Excel',
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.excelUpdate,
                          ),
                        ),
                      ),

                    // Orders & Customers
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Orders & Customers',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = Responsive.isDesktop(context) ? 4 : 2;
                        final spacing = 10.0;
                        final cardWidth =
                            (constraints.maxWidth - spacing * (cols - 1)) /
                            cols;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            SizedBox(
                              width: cardWidth,
                              child: _NavTile(
                                icon: Icons.receipt_long,
                                label: 'Purchase Orders',
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.purchaseOrders,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _NavTile(
                                icon: Icons.local_shipping,
                                label: 'Sales Orders',
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.salesOrders,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _NavTile(
                                icon: Icons.assignment_return,
                                label: 'Returns',
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.returns,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _NavTile(
                                icon: Icons.people,
                                label: 'Customers',
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.customers,
                                ),
                              ),
                            ),
                            if (context
                                .watch<BillingSettingsProvider>()
                                .billingEnabled)
                              SizedBox(
                                width: cardWidth,
                                child: _NavTile(
                                  icon: Icons.receipt_long_rounded,
                                  label: 'Billing',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.invoices,
                                  ),
                                ),
                              ),
                            if (context
                                    .watch<BillingSettingsProvider>()
                                    .billingEnabled &&
                                perms['canUseFastPos'] == true)
                              SizedBox(
                                width: cardWidth,
                                child: _NavTile(
                                  icon: Icons.point_of_sale_rounded,
                                  label: 'Fast POS',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.fastPos,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),

                    // Smart Inventory
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Smart Inventory',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = Responsive.isDesktop(context) ? 4 : 2;
                        final spacing = 10.0;
                        final cardWidth =
                            (constraints.maxWidth - spacing * (cols - 1)) /
                            cols;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            if (context
                                .watch<SettingsProvider>()
                                .barcodeEnabled)
                              SizedBox(
                                width: cardWidth,
                                child: _NavTile(
                                  icon: Icons.qr_code_scanner,
                                  label: 'Barcode Scanner',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.barcodeScanner,
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: cardWidth,
                              child: _NavTile(
                                icon: Icons.layers,
                                label: 'Batch Tracking',
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.batches,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _NavTile(
                                icon: Icons.shopping_cart_checkout,
                                label: 'Reorder',
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.reorderSuggestions,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _NavTile(
                                icon: Icons.trending_up,
                                label: 'Stock Forecast',
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.stockForecast,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _NavTile(
                                icon: Icons.fact_check,
                                label: 'Stock Take',
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.stockTakes,
                                ),
                              ),
                            ),
                            if (perms['canViewStockHolds'] == true)
                              SizedBox(
                                width: cardWidth,
                                child: _NavTile(
                                  icon: Icons.lock_clock_rounded,
                                  label: 'Stock Holds',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.stockHolds,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    const _RecentActivity(),
                  ],
                ),
              ),
            ),
          ),
          if (speedDialItems.isNotEmpty)
            Positioned(
              right: 16,
              bottom: 16,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 400),
                curve: Curves.elasticOut,
                builder: (context, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: FloatingActionButton(
                  heroTag: 'speed_dial_main',
                  tooltip: 'Quick actions',
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  onPressed: () =>
                      _showQuickActionsSheet(context, speedDialItems),
                  child: const Icon(Icons.flash_on_rounded),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wideActionButtons(BuildContext context, Map<String, bool> perms) {
    final buttons = _buildActionButtons(context, perms);
    if (buttons.isEmpty) return const SizedBox.shrink();
    final spaced =
        buttons
            .expand((b) => [Expanded(child: b), const SizedBox(width: 12)])
            .toList()
          ..removeLast();
    return Row(children: spaced);
  }

  Widget _narrowActionButtons(BuildContext context, Map<String, bool> perms) {
    final buttons = _buildActionButtons(context, perms);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: buttons
              .map((b) => SizedBox(width: itemWidth, child: b))
              .toList(),
        );
      },
    );
  }

  List<Widget> _buildActionButtons(
    BuildContext context,
    Map<String, bool> perms,
  ) {
    final billingOn = context.watch<BillingSettingsProvider>().billingEnabled;
    final settings = context.watch<SettingsProvider>();
    final actions = context
        .watch<HomeCustomizationProvider>()
        .getVisibleActions(
          perms,
          billingEnabled: billingOn,
          barcodeEnabled: settings.barcodeEnabled,
          vendorsEnabled: settings.vendorsEnabled,
          pricingEnabled: settings.pricingEnabled,
        );
    return actions
        .map(
          (action) => _ActionCard(
            icon: action.icon,
            label: action.label,
            gradient: action.gradient,
            onTap: () => Navigator.pushNamed(context, action.route),
          ),
        )
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Action Card (grid-style)
// ---------------------------------------------------------------------------
class _ActionCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              gradient: widget.gradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: widget.gradient.colors.first.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick stats row
// ---------------------------------------------------------------------------
class _QuickStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final perms = context.select<AuthProvider, Map<String, bool>>(
      (a) =>
          a.currentUser?.effectivePermissions ?? UserModel.defaultPermissions,
    );

    final isInitialLoading = context.select<ProductProvider, bool>(
      (p) => p.isLoading,
    );
    final isRefiningData = context.select<ProductProvider, bool>(
      (p) => p.isLoadingAnalytics && !p.isAnalyticsLoaded,
    );
    final totalProducts = context.select<ProductProvider, int>(
      (p) => p.totalProducts,
    );
    final lowStock = context.select<ProductProvider, int>(
      (p) => p.lowStockCount,
    );
    final outOfStock = context.select<ProductProvider, int>(
      (p) => p.outOfStockCount,
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

    int tabIndexFor(String tabLabel) {
      int idx = 1;
      if (tabLabel == 'Products' && perms['canViewProducts'] == true) {
        return idx;
      }
      if (perms['canViewProducts'] == true) idx++;
      if (tabLabel == 'Reports' && perms['canViewReports'] == true) return idx;
      return -1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isRefiningData)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(
                minHeight: 2,
                color: AppTheme.primaryColor,
                backgroundColor: Color(0x1A007AFF),
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = Responsive.isDesktop(context) ? 4 : 2;
            final spacing = 10.0;
            final cardWidth =
                (constraints.maxWidth - spacing * (cols - 1)) / cols;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                AnimatedListItem(
                  index: 0,
                  child: SizedBox(
                    width: cardWidth,
                    child: _StatCard(
                      label: 'Products',
                      value: totalProducts,
                      icon: Icons.inventory_2_rounded,
                      color: AppTheme.primaryColor,
                      isLoading: isInitialLoading,
                      onTap: () {
                        final idx = tabIndexFor('Products');
                        if (idx > 0) {
                          context
                              .findAncestorStateOfType<HomeScreenState>()
                              ?.switchToTab(idx);
                        }
                      },
                    ),
                  ),
                ),
                AnimatedListItem(
                  index: 1,
                  child: SizedBox(
                    width: cardWidth,
                    child: _StatCard(
                      label: 'Low Stock',
                      value: lowStock,
                      icon: Icons.warning_amber_rounded,
                      color: lowStock > 0
                          ? AppTheme.warningColor
                          : AppTheme.successColor,
                      isLoading: isInitialLoading,
                      onTap: () {
                        Navigator.pushNamed(context, AppRoutes.lowStock);
                      },
                    ),
                  ),
                ),
                AnimatedListItem(
                  index: 2,
                  child: SizedBox(
                    width: cardWidth,
                    child: _StatCard(
                      label: 'Out of Stock',
                      value: outOfStock,
                      icon: Icons.remove_shopping_cart_rounded,
                      color: AppTheme.dangerColor,
                      isLoading: isInitialLoading,
                      onTap: () {
                        final idx = tabIndexFor('Products');
                        if (idx > 0) {
                          context.read<ProductProvider>().filterByStockStatus(
                            'out_of_stock',
                          );
                          context
                              .findAncestorStateOfType<HomeScreenState>()
                              ?.switchToTab(idx);
                        }
                      },
                    ),
                  ),
                ),
                AnimatedListItem(
                  index: 3,
                  child: SizedBox(
                    width: cardWidth,
                    child: _StatCard(
                      label: 'Today',
                      value: todayTxns,
                      icon: Icons.receipt_long_rounded,
                      color: AppTheme.infoColor,
                      onTap: () {
                        final idx = tabIndexFor('Reports');
                        if (idx > 0) {
                          context
                              .findAncestorStateOfType<HomeScreenState>()
                              ?.switchToTab(idx);
                        }
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool isLoading;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: isLoading ? null : onTap,
      borderRadius: 16,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: value),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, val, _) => Text(
                      '$val',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSec(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick link button
// ---------------------------------------------------------------------------
class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      borderRadius: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppTheme.iconMute(context),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact nav tile for grid sections
// ---------------------------------------------------------------------------
class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      borderRadius: 14,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPri(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Insights Card (auto-rotating)
// ---------------------------------------------------------------------------
class _InsightItem {
  final IconData icon;
  final String text;
  final String route;
  const _InsightItem(this.icon, this.text, this.route);
}

class _InsightsCard extends StatefulWidget {
  const _InsightsCard();

  @override
  State<_InsightsCard> createState() => _InsightsCardState();
}

class _InsightsCardState extends State<_InsightsCard> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _index++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lowStockCount = context.select<ProductProvider, int>(
      (p) => p.lowStockCount,
    );
    final outOfStockCount = context.select<ProductProvider, int>(
      (p) => p.outOfStockCount,
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

    final insights = <_InsightItem>[
      _InsightItem(
        Icons.warning_amber_rounded,
        'You have $lowStockCount products below reorder level',
        AppRoutes.lowStock,
      ),
      _InsightItem(
        Icons.receipt_long_rounded,
        'Total $todayTxns transactions today',
        AppRoutes.transactionHistory,
      ),
      _InsightItem(
        Icons.remove_shopping_cart_rounded,
        '$outOfStockCount products out of stock',
        AppRoutes.lowStock,
      ),
    ];

    if (insights.isEmpty) return const SizedBox.shrink();

    final current = insights[_index % insights.length];

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, current.route),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryColor.withValues(alpha: 0.08),
              AppTheme.warningColor.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.warningColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.lightbulb_rounded,
                color: AppTheme.warningColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Row(
                  key: ValueKey<int>(_index % insights.length),
                  children: [
                    Icon(
                      current.icon,
                      size: 16,
                      color: AppTheme.textSec(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        current.text,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppTheme.iconMute(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Favorites quick access
// ---------------------------------------------------------------------------
class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection();

  @override
  Widget build(BuildContext context) {
    final favProvider = context.watch<FavoritesProvider>();
    final productProvider = context.watch<ProductProvider>();

    final favIds = favProvider.ids;
    if (favIds.isEmpty) return const SizedBox.shrink();

    final favProducts = productProvider.allProducts
        .where((p) => favIds.contains(p.id))
        .toList();
    if (favProducts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: AppTheme.dangerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Favorites',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPri(context),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, AppRoutes.favorites),
              child: Text(
                'View All',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (Responsive.isDesktop(context))
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: favProducts.map((product) {
              return GestureDetector(
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.productDetail,
                  arguments: product,
                ),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.dividerC(context)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        size: 14,
                        color: AppTheme.dangerColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        product.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          )
        else
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: favProducts.length,
              separatorBuilder: (_, index) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final product = favProducts[i];
                return GestureDetector(
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.productDetail,
                    arguments: product,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface(context),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.dividerC(context)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite_rounded,
                          size: 14,
                          color: AppTheme.dangerColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          product.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPri(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tip of the Day
// ---------------------------------------------------------------------------
class _TipOfTheDay extends StatefulWidget {
  const _TipOfTheDay();

  @override
  State<_TipOfTheDay> createState() => _TipOfTheDayState();
}

class _TipOfTheDayState extends State<_TipOfTheDay> {
  static const _tips = [
    'Use the barcode scanner to quickly find products by scanning their barcode.',
    'Set low stock thresholds on each product so you get alerts before running out.',
    'Export your inventory to Excel for easy sharing with your team.',
    'Use the Stock Transfer feature to move items between warehouse locations.',
    'Check the Dashboard regularly for visual insights into your inventory health.',
    'Use the Damage Report to track and write off damaged goods properly.',
    'Create purchase orders to streamline your restocking workflow.',
    'Use batch tracking to monitor product expiry dates and lot numbers.',
    'The ABC Analysis report helps you focus on your highest-value products.',
    'Set up staff permissions to control who can perform stock operations.',
    'Use the audit log to track every change made in the system.',
    'Pin your most-used products as favorites for quick access from Home.',
    'The profit & loss report gives you a clear picture of your margins.',
    'Use the global search to find any product, vendor, or transaction instantly.',
  ];

  bool _dismissed = false;
  bool _loaded = false;

  String get _prefKey =>
      'tip_dismissed_${DateFormat('yyyy-MM-dd').format(DateTime.now())}';

  @override
  void initState() {
    super.initState();
    _checkDismissed();
  }

  Future<void> _checkDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_prefKey) ?? false;
    if (mounted) {
      setState(() {
        _dismissed = dismissed;
        _loaded = true;
      });
    }
  }

  Future<void> _dismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _dismissed) return const SizedBox.shrink();

    final dayIndex = DateTime.now().difference(DateTime(2024)).inDays;
    final tip = _tips[dayIndex % _tips.length];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.infoColor.withValues(alpha: 0.08),
            AppTheme.primaryColor.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.infoColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.infoColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.lightbulb_rounded,
              color: AppTheme.infoColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tip of the Day',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.infoColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tip,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppTheme.textPri(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: AppTheme.iconMute(context),
            ),
            tooltip: 'Dismiss',
            onPressed: _dismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent activity
// ---------------------------------------------------------------------------
class _RecentActivity extends StatelessWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context) {
    final recent = context.select<StockProvider, List<StockTransactionModel>>(
      (s) => s.allTransactions.take(5).toList(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Recent Activity',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPri(context),
              ),
            ),
            const Spacer(),
            if (recent.isNotEmpty)
              GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, AppRoutes.transactionHistory);
                },
                child: Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          GlassPanel(
            borderRadius: 20,
            padding: const EdgeInsets.all(20),
            useContentVariant: true,
            child: Column(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 40,
                  color: AppTheme.emptyIcon(context),
                ),
                const SizedBox(height: 8),
                Text(
                  'No recent transactions',
                  style: TextStyle(
                    color: AppTheme.textTer(context),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )
        else
          ...recent.map((txn) => _TransactionTile(txn: txn)),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final StockTransactionModel txn;
  const _TransactionTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (txn.type) {
      TransactionType.stockIn => (
        Icons.add_circle_rounded,
        AppTheme.successColor,
      ),
      TransactionType.stockOut => (
        Icons.remove_circle_rounded,
        AppTheme.primaryColor,
      ),
      TransactionType.damage => (
        Icons.broken_image_rounded,
        AppTheme.dangerColor,
      ),
      TransactionType.transfer => (
        Icons.swap_horiz_rounded,
        AppTheme.indigoColor,
      ),
      TransactionType.adjustment => (Icons.tune_rounded, AppTheme.warningColor),
      TransactionType.hold => (
        Icons.pause_circle_rounded,
        AppTheme.warningColor,
      ),
      TransactionType.holdRelease => (
        Icons.play_circle_rounded,
        AppTheme.successColor,
      ),
    };

    final typeLabel = switch (txn.type) {
      TransactionType.stockIn => 'IN',
      TransactionType.stockOut => 'OUT',
      TransactionType.damage => 'DMG',
      TransactionType.transfer => 'TFR',
      TransactionType.adjustment => 'ADJ',
      TransactionType.hold => 'HLD',
      TransactionType.holdRelease => 'REL',
    };

    final now = DateTime.now();
    final diff = now.difference(txn.date);
    String timeAgo;
    if (diff.inMinutes < 1) {
      timeAgo = 'Just now';
    } else if (diff.inMinutes < 60) {
      timeAgo = '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      timeAgo = '${diff.inHours}h ago';
    } else {
      timeAgo = '${diff.inDays}d ago';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GlassCard(
        onTap: () {
          final product = context
              .read<ProductProvider>()
              .allProducts
              .where((p) => p.id == txn.productId)
              .firstOrNull;
          if (product != null) {
            Navigator.pushNamed(
              context,
              AppRoutes.productDetail,
              arguments: product,
            );
          }
        },
        borderRadius: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      txn.productName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      txn.location,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTer(context),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$typeLabel ${txn.quantity}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textTer(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedDialItem {
  final IconData icon;
  final String label;
  final Color color;
  final String route;
  const _SpeedDialItem(this.icon, this.label, this.color, this.route);
}
