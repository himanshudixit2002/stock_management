import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/stock_provider.dart';
import '../config/theme.dart';
import '../models/user_model.dart';
import '../models/stock_transaction_model.dart';
import '../utils/responsive.dart';
import 'products/product_list_screen.dart';
import 'reports/reports_screen.dart';
import 'settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isWide(context);

    final auth = context.watch<AuthProvider>();
    final perms = auth.currentUser?.effectivePermissions ?? UserModel.defaultPermissions;

    final tabs = <_TabItem>[
      _TabItem(Icons.home_rounded, Icons.home_outlined, 'Home', const _HomeTab()),
      if (perms['canViewProducts'] == true)
        _TabItem(Icons.inventory_2_rounded, Icons.inventory_2_outlined, 'Products', const ProductListScreen()),
      if (perms['canViewReports'] == true)
        _TabItem(Icons.analytics_rounded, Icons.analytics_outlined, 'Reports', const ReportsScreen()),
      _TabItem(Icons.settings_rounded, Icons.settings_outlined, 'Settings', const SettingsScreen()),
    ];

    final safeIndex = _currentIndex.clamp(0, tabs.length - 1);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
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
                onDestinationSelected: (i) => setState(() => _currentIndex = i),
                labelType: NavigationRailLabelType.all,
                backgroundColor: Colors.transparent,
                indicatorColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                selectedIconTheme: const IconThemeData(color: AppTheme.primaryColor, size: 24),
                unselectedIconTheme: IconThemeData(color: Colors.grey[500], size: 22),
                selectedLabelTextStyle: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                unselectedLabelTextStyle: TextStyle(
                  color: Colors.grey[500],
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
                    .map((t) => NavigationRailDestination(
                          icon: Icon(t.inactiveIcon),
                          selectedIcon: Icon(t.icon),
                          label: Text(t.label),
                        ))
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
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: safeIndex,
        children: tabs.map((t) => t.body).toList(),
      ),
      bottomNavigationBar: _CustomBottomNav(
        currentIndex: safeIndex,
        tabs: tabs,
        onTap: (i) => setState(() => _currentIndex = i),
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
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
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
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            isSelected ? tab.icon : tab.inactiveIcon,
                            color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                            size: isSelected ? 24 : 22,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: isSelected ? 11 : 10,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final perms = user.effectivePermissions;
    final isWide = Responsive.isWide(context);

    final initials = user.name.isNotEmpty
        ? user.name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : '?';

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
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
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient,
                  borderRadius: BorderRadius.circular(20),
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
                        radius: 26,
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
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome back,',
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
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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

              if (perms['canManageCategories'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _QuickLink(
                    icon: Icons.category_rounded,
                    label: 'Manage Categories',
                    onTap: () => Navigator.pushNamed(context, '/categories'),
                  ),
                ),

              const _RecentActivity(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wideActionButtons(BuildContext context, Map<String, bool> perms) {
    final buttons = _buildActionButtons(context, perms);
    return Row(
      children: buttons
          .expand((b) => [Expanded(child: b), const SizedBox(width: 12)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _narrowActionButtons(BuildContext context, Map<String, bool> perms) {
    final buttons = _buildActionButtons(context, perms);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: buttons.map((b) => SizedBox(
            width: itemWidth,
            child: b,
          )).toList(),
        );
      },
    );
  }

  List<Widget> _buildActionButtons(BuildContext context, Map<String, bool> perms) {
    final List<Widget> buttons = [];

    if (perms['canStockIn'] == true) {
      buttons.add(_ActionCard(
        icon: Icons.add_circle_rounded,
        label: 'Stock In',
        gradient: AppTheme.successGradient,
        onTap: () => Navigator.pushNamed(context, '/stock/in'),
      ));
    }
    if (perms['canStockOut'] == true) {
      buttons.add(_ActionCard(
        icon: Icons.remove_circle_rounded,
        label: 'Stock Out',
        gradient: AppTheme.primaryGradient,
        onTap: () => Navigator.pushNamed(context, '/stock/out'),
      ));
    }
    if (perms['canDamage'] == true) {
      buttons.add(_ActionCard(
        icon: Icons.broken_image_rounded,
        label: 'Damage',
        gradient: AppTheme.dangerGradient,
        onTap: () => Navigator.pushNamed(context, '/stock/damage'),
      ));
    }
    if (perms['canTransfer'] == true) {
      buttons.add(_ActionCard(
        icon: Icons.swap_horiz_rounded,
        label: 'Transfer',
        gradient: AppTheme.indigoGradient,
        onTap: () => Navigator.pushNamed(context, '/stock/transfer'),
      ));
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
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(18),
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 10),
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

    final totalProducts = productProvider.products.length;
    final lowStock = productProvider.lowStockProducts.length;
    final todayTxns = stockProvider.allTransactions
        .where((t) {
          final now = DateTime.now();
          return t.date.year == now.year &&
              t.date.month == now.month &&
              t.date.day == now.day;
        })
        .length;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Products',
            value: totalProducts,
            icon: Icons.inventory_2_rounded,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Low Stock',
            value: lowStock,
            icon: Icons.warning_amber_rounded,
            color: lowStock > 0 ? AppTheme.warningColor : AppTheme.successColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Today',
            value: todayTxns,
            icon: Icons.receipt_long_rounded,
            color: AppTheme.infoColor,
          ),
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

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<int>(
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
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppTheme.cardShadow,
          ),
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
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[400], size: 16),
            ],
          ),
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
                color: Colors.grey[800],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: AppTheme.cardDecoration,
            child: Column(
              children: [
                Icon(Icons.history_rounded, size: 40, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text(
                  'No recent transactions',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
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
      TransactionType.stockIn => (Icons.add_circle_rounded, AppTheme.successColor),
      TransactionType.stockOut => (Icons.remove_circle_rounded, AppTheme.primaryColor),
      TransactionType.damage => (Icons.broken_image_rounded, AppTheme.dangerColor),
      TransactionType.transfer => (Icons.swap_horiz_rounded, AppTheme.indigoColor),
    };

    final typeLabel = switch (txn.type) {
      TransactionType.stockIn => 'IN',
      TransactionType.stockOut => 'OUT',
      TransactionType.damage => 'DMG',
      TransactionType.transfer => 'TFR',
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

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadow,
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.productName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  txn.location,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
