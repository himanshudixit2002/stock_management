import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/stock_transaction_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/animations.dart';
import '../../widgets/glass_panel.dart';
import '../home_screen.dart';

// ---------------------------------------------------------------------------
// Action card (customizable Quick Actions surface on Home)
// ---------------------------------------------------------------------------
class HomeActionCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const HomeActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<HomeActionCard> createState() => _HomeActionCardState();
}

class _HomeActionCardState extends State<HomeActionCard> {
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
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
class QuickStats extends StatelessWidget {
  const QuickStats({super.key});

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
                ? Container(
                    width: 40,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppTheme.dividerC(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  )
                : CountUpText(
                    value,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: color,
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
// Compact nav tile for grid sections
// ---------------------------------------------------------------------------
class HomeNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;

  const HomeNavTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.primaryColor;
    return FadeSlideIn(
      child: GlassCard(
        onTap: onTap,
        borderRadius: 14,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              AnimatedIconBadge(icon: icon, color: accent, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPri(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textTer(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
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
// Insights Card (auto-rotating)
// ---------------------------------------------------------------------------
class _InsightItem {
  final IconData icon;
  final String text;
  final String route;
  const _InsightItem(this.icon, this.text, this.route);
}

class InsightsCard extends StatefulWidget {
  const InsightsCard({super.key});

  @override
  State<InsightsCard> createState() => _InsightsCardState();
}

class _InsightsCardState extends State<InsightsCard> {
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
class FavoritesSection extends StatelessWidget {
  const FavoritesSection({super.key});

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
class TipOfTheDay extends StatefulWidget {
  const TipOfTheDay({super.key});

  @override
  State<TipOfTheDay> createState() => _TipOfTheDayState();
}

class _TipOfTheDayState extends State<TipOfTheDay> {
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
class RecentActivity extends StatelessWidget {
  const RecentActivity({super.key});

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
