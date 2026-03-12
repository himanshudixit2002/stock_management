import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/stock_provider.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../models/user_model.dart';
import '../models/stock_transaction_model.dart';
import '../utils/responsive.dart';
import 'products/product_list_screen.dart';
import 'reports/reports_screen.dart';
import 'settings/settings_screen.dart';
import '../widgets/glass_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  DateTime? _lastBackPress;

  void switchToTab(int index) {
    setState(() => _currentIndex = index);
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
    _loadAnalyticsIfNeeded(index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAnalyticsIfNeeded(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isWide(context);

    final auth = context.watch<AuthProvider>();
    final perms =
        auth.currentUser?.effectivePermissions ?? UserModel.defaultPermissions;

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
        backgroundColor: AppTheme.backgroundColor,
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.scaffoldGradient),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor,
                  border: Border(
                    right: BorderSide(color: AppTheme.dividerColor, width: 1),
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
                  backgroundColor: Colors.transparent,
                  indicatorColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                  selectedIconTheme: const IconThemeData(
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                  unselectedIconTheme: IconThemeData(
                    color: AppTheme.iconMuted,
                    size: 22,
                  ),
                  selectedLabelTextStyle: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  unselectedLabelTextStyle: TextStyle(
                    color: AppTheme.iconMuted,
                    fontSize: 11,
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
                child: IndexedStack(
                  index: safeIndex,
                  children: tabs.map((t) => t.body).toList(),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      scaffold = Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.scaffoldGradient),
          child: IndexedStack(
            index: safeIndex,
            children: tabs.map((t) => t.body).toList(),
          ),
        ),
        bottomNavigationBar: _CustomBottomNav(
          currentIndex: safeIndex,
          tabs: tabs,
          onTap: (i) => _onTabSelected(i),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppTheme.surfaceColor,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final now = DateTime.now();
          if (_lastBackPress != null &&
              now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
            Navigator.of(context).pop();
            return;
          }
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: scaffold,
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
        color: AppTheme.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppTheme.dividerColor, width: 1)),
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
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
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
                    padding: const EdgeInsets.symmetric(vertical: 6),
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
                                : AppTheme.textTertiary,
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
                                : AppTheme.textTertiary,
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
class _HomeTab extends StatelessWidget {
  const _HomeTab();

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
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

    return SafeArea(
      child: Center(
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
                20,
                Responsive.horizontalPadding(context),
                32,
              ),
              children: [
                // Profile bar
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: AppTheme.heroGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.coloredShadow(AppTheme.primaryColor),
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
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
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
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  user.companyName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.95),
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

                const SizedBox(height: 24),

                // Action buttons
                if (isWide)
                  _wideActionButtons(context, perms)
                else
                  _narrowActionButtons(context, perms),

                const SizedBox(height: 24),

                _QuickStats(),

                const SizedBox(height: 24),

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
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.damageHistory),
                    ),
                  ),

                if (perms['canManageCategories'] == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _QuickLink(
                      icon: Icons.category_rounded,
                      label: 'Manage Categories',
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.categories),
                    ),
                  ),

                if (perms['canImport'] == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _QuickLink(
                      icon: Icons.sync_rounded,
                      label: 'Update from Excel',
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.excelUpdate),
                    ),
                  ),

                const _RecentActivity(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wideActionButtons(BuildContext context, Map<String, bool> perms) {
    final buttons = _buildActionButtons(context, perms);
    if (buttons.isEmpty) return const SizedBox.shrink();
    final spaced = buttons
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
    final List<Widget> buttons = [];

    if (perms['canStockIn'] == true) {
      buttons.add(
        _ActionCard(
          icon: Icons.add_circle_rounded,
          label: 'Stock In',
          gradient: AppTheme.successGradient,
          onTap: () => Navigator.pushNamed(context, AppRoutes.stockIn),
        ),
      );
    }
    if (perms['canStockOut'] == true) {
      buttons.add(
        _ActionCard(
          icon: Icons.remove_circle_rounded,
          label: 'Stock Out',
          gradient: AppTheme.primaryGradient,
          onTap: () => Navigator.pushNamed(context, AppRoutes.stockOut),
        ),
      );
    }
    if (perms['canDamage'] == true) {
      buttons.add(
        _ActionCard(
          icon: Icons.broken_image_rounded,
          label: 'Damage',
          gradient: AppTheme.dangerGradient,
          onTap: () => Navigator.pushNamed(context, AppRoutes.damageReport),
        ),
      );
    }
    if (perms['canTransfer'] == true) {
      buttons.add(
        _ActionCard(
          icon: Icons.swap_horiz_rounded,
          label: 'Transfer',
          gradient: AppTheme.indigoGradient,
          onTap: () => Navigator.pushNamed(context, AppRoutes.stockTransfer),
        ),
      );
    }
    if (perms['canAdjustStock'] == true) {
      buttons.add(
        _ActionCard(
          icon: Icons.tune_rounded,
          label: 'Adjust',
          gradient: AppTheme.warningGradient,
          onTap: () => Navigator.pushNamed(context, AppRoutes.stockAdjustment),
        ),
      );
    }

    return buttons;
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
    return GestureDetector(
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
    );
  }
}

// ---------------------------------------------------------------------------
// Quick stats row
// ---------------------------------------------------------------------------
class _QuickStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final productProvider = context.watch<ProductProvider>();
    final stockProvider = context.watch<StockProvider>();
    final auth = context.watch<AuthProvider>();
    final perms =
        auth.currentUser?.effectivePermissions ?? UserModel.defaultPermissions;

    final isInitialLoading = productProvider.isLoading;
    final isRefiningData = productProvider.isLoadingAnalytics &&
        !productProvider.isAnalyticsLoaded;
    final totalProducts = productProvider.totalProducts;
    final lowStock = productProvider.lowStockCount;
    final outOfStock = productProvider.outOfStockCount;
    final todayTxns = stockProvider.allTransactions.where((t) {
      final now = DateTime.now();
      return t.date.year == now.year &&
          t.date.month == now.month &&
          t.date.day == now.day;
    }).length;

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
            final cardWidth = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
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
                SizedBox(
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
                SizedBox(
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
                        productProvider.filterByStockStatus('out_of_stock');
                        context
                            .findAncestorStateOfType<HomeScreenState>()
                            ?.switchToTab(idx);
                      }
                    },
                  ),
                ),
                SizedBox(
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
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
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
              color: AppTheme.iconMuted,
              size: 16,
            ),
          ],
        ),
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
    final transactions = context.watch<StockProvider>().allTransactions;
    final recent = transactions.take(5).toList();

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
                color: AppTheme.textPrimary,
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
            padding: const EdgeInsets.all(32),
            useContentVariant: true,
            child: Column(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 40,
                  color: AppTheme.emptyStateIcon,
                ),
                const SizedBox(height: 8),
                Text(
                  'No recent transactions',
                  style: TextStyle(color: AppTheme.textTertiary, fontSize: 14),
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
    };

    final typeLabel = switch (txn.type) {
      TransactionType.stockIn => 'IN',
      TransactionType.stockOut => 'OUT',
      TransactionType.damage => 'DMG',
      TransactionType.transfer => 'TFR',
      TransactionType.adjustment => 'ADJ',
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
                        color: AppTheme.textTertiary,
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
                      color: AppTheme.textTertiary,
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
