import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/feature_map.dart';
import '../../config/feature_visibility.dart';
import '../../config/motion.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/home_customization_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/product_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/animations.dart';
import '../../widgets/floating_nav_padding.dart';
import '../../widgets/ai/autonomous_dashboard_widget.dart';
import 'getting_started_card.dart';
import 'home_sections.dart';

/// The Home tab body, built from [HomeSection]s the user can switch on and off
/// in Home customization.
///
/// It shows only what the signed-in user can use: every block, card and tile is
/// filtered through [FeatureVisibility] (permissions, workspace switches and
/// hidden modules, plan). It used to stack nine blocks for everyone, including a
/// rotating insights strip and a second "Today" row that repeated the stat
/// cards, so a phone showed the same low-stock number three times before the
/// first feature tile.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final vis = FeatureVisibility.watch(context);
    final layout = context.watch<HomeCustomizationProvider>();

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

    final actions = layout.isSectionVisible(HomeSection.quickActions)
        ? layout.visibleActions(vis)
        : const [];

    // The AI panel sends cost and selling prices to the assistant backend, so
    // it needs the report permission as well as a plan that includes it.
    final showAi =
        layout.isSectionVisible(HomeSection.aiInsights) &&
        vis.allowsId('aiAssistant') &&
        vis.has(AppPermissions.viewReports);

    // Each section with whether it spaces itself. Those that may turn out to
    // have nothing to show (the checklist once it is done, "Show more" with
    // no favorites or tip) put the gap above themselves only when they do; a
    // fixed gap left an empty band where they rendered nothing.
    const gap = 16.0;
    final sections = <(Widget, bool)>[
      if (actions.isNotEmpty)
        (
          _QuickActionsSection(
            actions: [
              for (final a in actions)
                HomeActionCard(
                  icon: a.icon,
                  label: a.label,
                  gradient: a.gradient,
                  onTap: () => Navigator.pushNamed(context, a.route),
                ),
            ],
          ),
          false,
        ),
      if (layout.isSectionVisible(HomeSection.stats)) (const QuickStats(), false),
      // The checklist is an admin's setup list.
      if (user.isAdmin && layout.isSectionVisible(HomeSection.gettingStarted))
        (const GettingStartedCard(topGap: gap), true),
      if (showAi) (const AutonomousDashboardWidget(), false),
      if (layout.isSectionVisible(HomeSection.favoritesAndTips))
        (const _HomeMoreSection(topGap: gap), true),
      if (layout.isSectionVisible(HomeSection.featureShortcuts))
        for (final grid in _buildCategoryGrids(
          context,
          vis,
          // A feature already pinned as a quick action is not repeated as a
          // tile further down.
          quickActionRoutes: {for (final a in actions) a.route},
        ))
          (grid, false),
      if (layout.isSectionVisible(HomeSection.recentActivity))
        (
          RecentActivity(
            showViewAll:
                vis.allowsId('transactionHistory') ||
                vis.has(AppPermissions.viewReports),
          ),
          false,
        ),
    ];

    return SafeArea(
      // The bottom inset is owned by [floatingNavContentInset] (via the
      // trailing FloatingNavPadding), which already accounts for the gesture
      // bar. Letting SafeArea add it too would double-count it.
      bottom: false,
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
                8,
                Responsive.horizontalPadding(context),
                24,
              ),
              children: [
                _buildTopBar(context, user.name, initials, user),
                _buildUpdatedLabel(context),
                const SizedBox(height: 10),
                // One gap between sections, whichever are switched on. Fixed
                // spacers around each block left double gaps where a block was
                // hidden or rendered nothing.
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0 && !sections[i].$2) const SizedBox(height: gap),
                  sections[i].$1,
                ],
                const FloatingNavPadding(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Merged top bar: avatar + greeting + search + notifications (single header)
  // ---------------------------------------------------------------------------
  Widget _buildTopBar(
    BuildContext context,
    String name,
    String initials,
    UserModel user,
  ) {
    final firstName = name.trim().split(' ').firstOrNull ?? name;
    final multiCompany = user.companyMemberships.length > 1;

    final avatar = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppTheme.heroGrad(context),
      ),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: Colors.transparent,
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.onPrimary(context),
          ),
        ),
      ),
    );

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          if (multiCompany)
            Semantics(
              button: true,
              label: 'Switch company',
              child: InkWell(
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.companySwitcher),
                borderRadius: BorderRadius.circular(22),
                child: avatar,
              ),
            )
          else
            avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hi, $firstName',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPri(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user.companyName.isNotEmpty)
                  Text(
                    user.companyName,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSec(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.search_rounded, color: AppTheme.textSec(context)),
            tooltip: 'Search',
            onPressed: () => Navigator.pushNamed(context, AppRoutes.globalSearch),
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
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Icon(
                    Icons.notifications_outlined,
                    color: AppTheme.textSec(context),
                  ),
                ),
                tooltip: 'Notifications',
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.notifications),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatedLabel(BuildContext context) {
    return Selector<ProductProvider, DateTime?>(
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
          label = 'Updated ${DateFormat.jm().format(fetchedAt)}';
        }
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textTer(context),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Categorized discovery grid (single source of truth via FeatureMap)
  // ---------------------------------------------------------------------------
  List<Widget> _buildCategoryGrids(
    BuildContext context,
    FeatureVisibility vis, {
    required Set<String> quickActionRoutes,
  }) {
    final widgets = <Widget>[];
    for (final category in FeatureMap.homeGridCategories(
      vis.permissions,
      billingEnabled: vis.gates.billing,
      barcodeEnabled: vis.gates.barcode,
      vendorsEnabled: vis.gates.vendors,
      pricingEnabled: vis.gates.pricing,
      plan: vis.plan,
      hiddenFeatures: vis.gates.hiddenFeatures,
    )) {
      final entries =
          FeatureMap.entriesByCategory(
                category,
                vis.permissions,
                placement: FeaturePlacement.homeSecondary,
                billingEnabled: vis.gates.billing,
                barcodeEnabled: vis.gates.barcode,
                vendorsEnabled: vis.gates.vendors,
                pricingEnabled: vis.gates.pricing,
                plan: vis.plan,
                hiddenFeatures: vis.gates.hiddenFeatures,
              )
              .where((e) => !quickActionRoutes.contains(e.route))
              .toList();
      if (entries.isEmpty) continue;
      final meta = FeatureMap.categoryMeta[category]!;
      final accent = FeatureMap.categoryColor(category);

      widgets.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: meta.title, subtitle: meta.subtitle),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final cols = width >= 1000
                    ? 4
                    : width >= 640
                    ? 3
                    : 2;
                const spacing = 10.0;
                final cardWidth = (width - spacing * (cols - 1)) / cols;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final e in entries)
                      SizedBox(
                        width: cardWidth,
                        child: HomeNavTile(
                          icon: e.icon,
                          label: e.label,
                          // A two-column phone tile has room for the name and
                          // nothing else; the description only cut it short.
                          subtitle: cardWidth >= 220 ? e.subtitle : null,
                          color: accent,
                          onTap: () => Navigator.pushNamed(context, e.route),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    }
    return widgets;
  }
}

/// The user's quick action cards, in a grid whose columns follow the width.
///
/// Cards keep one width at every size. On wide screens they used to share a
/// single row, so a 600 px window squeezed six cards to 60 px each and a
/// 1440 px window stretched one or two of them across half the screen.
class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Quick Actions',
          padding: EdgeInsets.symmetric(vertical: 4),
        ),
        const SizedBox(height: 8),
        FadeSlideIn(
          index: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final cols = width >= 900
                  ? 6
                  : width >= 480
                  ? 4
                  : 3;
              const spacing = 10.0;
              final cardWidth = (width - spacing * (cols - 1)) / cols;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final card in actions)
                    SizedBox(width: cardWidth, child: card),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Tucks the secondary Favorites + Tip-of-the-Day surfaces behind a single
/// "Show more" expander so they don't push primary content below the fold.
/// Honors reduce-motion via the zero-duration [AnimatedCrossFade].
///
/// Renders nothing at all when there are no favorites and today's tip has been
/// dismissed: the expander used to stay on screen and open onto nothing.
class _HomeMoreSection extends StatefulWidget {
  const _HomeMoreSection({this.topGap = 0});

  /// Space above the section, applied only when it shows something.
  final double topGap;

  @override
  State<_HomeMoreSection> createState() => _HomeMoreSectionState();
}

class _HomeMoreSectionState extends State<_HomeMoreSection> {
  bool _expanded = false;

  /// Null until the saved dismissal has been read.
  bool? _tipDismissed;

  @override
  void initState() {
    super.initState();
    TipOfTheDay.isDismissedToday().then((dismissed) {
      if (mounted) setState(() => _tipDismissed = dismissed);
    });
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final hasFavorites = context.select<FavoritesProvider, bool>(
      (f) => f.ids.isNotEmpty,
    );
    final tipPending =
        _tipDismissed == false &&
        TipOfTheDay.tipFor(FeatureVisibility.watch(context)) != null;
    if (!hasFavorites && !tipPending) return const SizedBox.shrink();

    final reduce = reduceMotion(context);
    return Padding(
      padding: EdgeInsets.only(top: widget.topGap),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? 'Show less' : 'Show more',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: reduce
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasFavorites) const FadeSlideIn(child: FavoritesSection()),
                if (hasFavorites && tipPending) const SizedBox(height: 16),
                if (tipPending)
                  FadeSlideIn(
                    child: TipOfTheDay(
                      onDismissed: () => setState(() => _tipDismissed = true),
                    ),
                  ),
              ],
            ),
          ),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
      ),
    );
  }
}
