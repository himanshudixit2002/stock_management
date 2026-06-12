import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/motion.dart';
import '../config/theme.dart';
import '../providers/product_provider.dart';
import '../providers/stock_provider.dart';
import 'floating_nav_padding.dart';

/// Identifies a tab so the floating nav can attach the right live badge.
enum FloatingNavTabKind { home, products, reports, settings }

/// A single destination in the [FloatingBottomNav].
class FloatingNavTab {
  final IconData icon;
  final IconData inactiveIcon;
  final String label;
  final FloatingNavTabKind kind;

  const FloatingNavTab({
    required this.icon,
    required this.inactiveIcon,
    required this.label,
    required this.kind,
  });
}

/// A floating, pill-style bottom navigation bar. It is rendered as a `Stack`
/// overlay (NOT via `Scaffold.bottomNavigationBar`) so body content scrolls
/// behind it. Frosted glass (BackdropFilter on web, frosted surface on native),
/// a sliding active indicator, and a raised centre "Quick Actions" button.
///
/// Design choices (under-specified in the brief):
/// - Unselected tabs are **icon-only** (cleaner); the label fades in only for
///   the selected tab.
/// - The centre Quick Actions button is **always visible** (when any quick
///   action is permitted) so it is reachable consistently from every tab.
class FloatingBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<FloatingNavTab> tabs;
  final ValueChanged<int> onTap;

  /// Whether to show the raised centre Quick Actions button.
  final bool showQuickActions;

  /// Opens the categorized quick-actions sheet (owned by the shell).
  final VoidCallback? onQuickActions;

  const FloatingBottomNav({
    super.key,
    required this.currentIndex,
    required this.tabs,
    required this.onTap,
    this.showQuickActions = false,
    this.onQuickActions,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final showButton = showQuickActions && onQuickActions != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: bottomInset + kFloatingNavBarBottomGap,
      ),
      child: SizedBox(
        height:
            kFloatingNavBarHeight + (showButton ? kFloatingNavButtonOverhang : 0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: kFloatingNavBarHeight,
              child: _buildPill(context),
            ),
            if (showButton)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _CenterQuickActionsButton(onTap: onQuickActions!),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPill(BuildContext context) {
    final count = tabs.length;

    // Live badge data — read providers without mutating them.
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

    final reduce = reduceMotion(context);
    final isDark = AppTheme.isDark(context);

    final decoration = BoxDecoration(
      color: kIsWeb ? AppTheme.glassSurface(context) : AppTheme.surface(context),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: AppTheme.glassBorder(context), width: 1),
      boxShadow: [
        ...AppTheme.softShadow,
        // Subtle primary glow tied to the active selection.
        BoxShadow(
          color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.22 : 0.16),
          blurRadius: 22,
          spreadRadius: -2,
          offset: const Offset(0, 6),
        ),
      ],
    );

    final inner = LayoutBuilder(
      builder: (context, constraints) {
        final cellW = constraints.maxWidth / count;
        final indicatorW = (cellW - 18).clamp(44.0, 76.0);
        const indicatorH = 44.0;
        final indicatorLeft =
            currentIndex * cellW + (cellW - indicatorW) / 2;

        return Stack(
          children: [
            AnimatedPositioned(
              duration:
                  reduce ? Duration.zero : const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              left: indicatorLeft,
              top: (kFloatingNavBarHeight - indicatorH) / 2,
              width: indicatorW,
              height: indicatorH,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            Row(
              children: List.generate(count, (i) {
                final tab = tabs[i];
                return Expanded(
                  child: _FloatingNavItem(
                    tab: tab,
                    selected: i == currentIndex,
                    badge: _badgeFor(
                      context,
                      tab.kind,
                      outOfStock: outOfStock,
                      lowStock: lowStock,
                      todayTxns: todayTxns,
                    ),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onTap(i);
                    },
                  ),
                );
              }),
            ),
          ],
        );
      },
    );

    final container = DecoratedBox(decoration: decoration, child: inner);

    if (kIsWeb) {
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: container,
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: container,
      ),
    );
  }

  /// Live badge for a tab. Products: red out-of-stock count takes priority over
  /// amber low-stock count. Reports: a small dot when there is activity today.
  Widget? _badgeFor(
    BuildContext context,
    FloatingNavTabKind kind, {
    required int outOfStock,
    required int lowStock,
    required int todayTxns,
  }) {
    switch (kind) {
      case FloatingNavTabKind.products:
        if (outOfStock > 0) {
          return _CountBadge(count: outOfStock, color: AppTheme.dangerColor);
        }
        if (lowStock > 0) {
          return _CountBadge(count: lowStock, color: AppTheme.warningColor);
        }
        return null;
      case FloatingNavTabKind.reports:
        if (todayTxns > 0) {
          return const _DotBadge(color: AppTheme.infoColor);
        }
        return null;
      case FloatingNavTabKind.home:
      case FloatingNavTabKind.settings:
        return null;
    }
  }
}

class _FloatingNavItem extends StatefulWidget {
  final FloatingNavTab tab;
  final bool selected;
  final Widget? badge;
  final VoidCallback onTap;

  const _FloatingNavItem({
    required this.tab,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  State<_FloatingNavItem> createState() => _FloatingNavItemState();
}

class _FloatingNavItemState extends State<_FloatingNavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final selected = widget.selected;
    final color =
        selected ? AppTheme.primaryColor : AppTheme.textTer(context);

    final iconWithBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        // Selected icon gets a gentle bounce (easeOutBack overshoot).
        AnimatedScale(
          scale: selected ? 1.15 : 1.0,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: Icon(
            selected ? widget.tab.icon : widget.tab.inactiveIcon,
            color: color,
            size: 24,
          ),
        ),
        if (widget.badge != null)
          Positioned(right: -6, top: -5, child: widget.badge!),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: !reduce && _pressed ? 0.92 : 1.0,
        duration: kPressDuration,
        curve: kPressCurve,
        child: Semantics(
          button: true,
          selected: selected,
          label: widget.tab.label,
          child: SizedBox(
            height: kFloatingNavBarHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                iconWithBadge,
                AnimatedSize(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: selected
                      ? Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            widget.tab.label,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterQuickActionsButton extends StatefulWidget {
  final VoidCallback onTap;

  const _CenterQuickActionsButton({required this.onTap});

  @override
  State<_CenterQuickActionsButton> createState() =>
      _CenterQuickActionsButtonState();
}

class _CenterQuickActionsButtonState
    extends State<_CenterQuickActionsButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    const size = 54.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: !reduce && _pressed ? 0.92 : 1.0,
        duration: kPressDuration,
        curve: kPressCurve,
        child: Semantics(
          button: true,
          label: 'Quick actions',
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.surface(context),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _CountBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.surface(context), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _DotBadge extends StatelessWidget {
  final Color color;

  const _DotBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.surface(context), width: 1.5),
      ),
    );
  }
}
