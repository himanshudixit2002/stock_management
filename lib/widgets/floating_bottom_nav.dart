
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/motion.dart';
import '../config/theme.dart';
import '../providers/product_provider.dart';
import '../providers/stock_provider.dart';
import 'floating_nav_padding.dart';

/// Corner radius of the floating bar. Close to a stadium at this height, which
/// is what Apple's floating bars read as.
const double _kNavRadius = 26;

/// Identifies a tab so the floating nav can attach the right live badge.
enum FloatingNavTabKind { home, products, reports, ai, settings }

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

/// A floating bottom navigation bar, modelled on Apple's tab bars.
///
/// Rendered as a `Stack` overlay (NOT via `Scaffold.bottomNavigationBar`) so
/// body content scrolls behind it, with a raised centre "Quick Actions" button.
///
/// Three deliberate departures from the previous version, all of them things
/// Apple's own tab bars do not do:
///
/// * **No sliding indicator pill.** Selection is carried by the icon switching
///   from outlined to filled plus the accent colour — the same two signals
///   Apple uses. A travelling capsule behind the icons is the single most
///   "Material" thing a tab bar can do.
/// * **Labels are always visible**, not just under the selected tab. Showing
///   one label made the row reflow on every tap and left the other
///   destinations unnamed.
/// * **Neutral elevation.** The bar used to cast a coloured glow tinted with
///   the brand primary; a tab bar should recede, not advertise itself.
///
/// It is opaque on every platform. Apple's bars are translucent, but that
/// needs a live backdrop blur, and `BackdropFilter` was deliberately removed
/// from this app — on CanvasKit it re-blurred the region behind a persistent
/// overlay on every scroll frame. A clean opaque surface with a hairline
/// border reads better than a semi-transparent one with nothing blurred behind
/// it.
class FloatingBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<FloatingNavTab> tabs;
  final ValueChanged<int> onTap;

  /// Badge counts, normally read from the providers.
  ///
  /// Injectable because this is a presentation widget that otherwise reaches
  /// into ProductProvider and StockProvider itself — and those cannot be
  /// constructed without a live Firebase app, which made the bar impossible to
  /// render in a test. Left null in the app; supplied by tests.
  final int? outOfStockCount;
  final int? lowStockCount;
  final int? todayTransactionCount;

  const FloatingBottomNav({
    super.key,
    required this.currentIndex,
    required this.tabs,
    required this.onTap,
    this.outOfStockCount,
    this.lowStockCount,
    this.todayTransactionCount,
  });


  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: bottomInset + kFloatingNavBarBottomGap,
      ),
      child: SizedBox(
        height: kFloatingNavBarHeight,
        child: _buildPill(context),
      ),
    );
  }

  Widget _buildPill(BuildContext context) {
    final count = tabs.length;

    // Live badge data — read providers without mutating them, unless the
    // caller supplied the counts outright.
    final outOfStock = outOfStockCount ??
        context.select<ProductProvider, int>((p) => p.outOfStockCount);
    final lowStock = lowStockCount ??
        context.select<ProductProvider, int>((p) => p.lowStockCount);
    final todayTxns = todayTransactionCount ??
        context.select<StockProvider, int>((s) {
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

    final isDark = AppTheme.isDark(context);

    final decoration = BoxDecoration(
      color: AppTheme.surface(context),
      borderRadius: BorderRadius.circular(_kNavRadius),
      // A hairline, not a 1px line: at 0.5 logical pixels the border reads as
      // an edge rather than as a drawn stroke, which is what makes an Apple
      // bar look like a material rather than a widget.
      border: Border.all(
        color: AppTheme.dividerC(context),
        width: 0.5,
      ),
      // Neutral and soft. In dark mode a drop shadow is invisible against the
      // ground, so the hairline carries the separation on its own.
      boxShadow: isDark
          ? const []
          : const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
    );

    // No Stack and no travelling indicator: just the row. See the class doc.
    final inner = Row(
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
    );

    final container = DecoratedBox(decoration: decoration, child: inner);

    // The web build used to wrap this in a sigma-16 BackdropFilter. The nav is
    // a persistent overlay above scrolling content, so that re-blurred a full
    // pill-sized region of the backdrop on every scroll frame — the most
    // expensive thing on screen, permanently. Opaque on every platform now.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kNavRadius),
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
      case FloatingNavTabKind.ai:
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
    // The two signals Apple uses, and only those: fill and colour.
    final color = selected
        ? AppTheme.primary(context)
        : AppTheme.textTer(context);

    final iconWithBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        // A restrained lift, not a bounce. The old 1.15/easeOutBack overshoot
        // made the whole row visibly jump on every tap.
        AnimatedScale(
          scale: selected ? 1.06 : 1.0,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          // Cross-fades outlined into filled rather than swapping abruptly.
          child: AnimatedSwitcher(
            duration:
                reduce ? Duration.zero : const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Icon(
              selected ? widget.tab.icon : widget.tab.inactiveIcon,
              key: ValueKey(selected),
              color: color,
              size: 25,
            ),
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
        scale: !reduce && _pressed ? 0.94 : 1.0,
        duration: kPressDuration,
        curve: kPressCurve,
        child: Semantics(
          button: true,
          selected: selected,
          label: widget.tab.label,
          // The label is drawn, so it must not also be announced separately.
          child: ExcludeSemantics(
            child: SizedBox(
              height: kFloatingNavBarHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconWithBadge,
                  const SizedBox(height: 3),
                  // Always visible. Showing the label only for the selected tab
                  // reflowed the row on every tap and left the other
                  // destinations anonymous.
                  AnimatedDefaultTextStyle(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.1,
                      letterSpacing: 0.1,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: color,
                    ),
                    child: Text(
                      widget.tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      // Labels this small must not scale into the icon.
                      textScaler: TextScaler.noScaling,
                    ),
                  ),
                ],
              ),
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
              gradient: AppTheme.primaryGrad(context),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppTheme.surface(context),
                width: 3,
              ),
              // Toned down from 0.4: the bar around it is now neutral, and a
              // heavy coloured halo was the loudest thing on the screen.
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.28),
                  blurRadius: 14,
                  spreadRadius: -1,
                  offset: const Offset(0, 5),
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
      // A count glyph inside a fixed-height pill: stays small and opts out of
      // text scaling so a large system font cannot burst the badge.
      child: Text(
        count > 99 ? '99+' : '$count',
        textScaler: TextScaler.noScaling,
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
