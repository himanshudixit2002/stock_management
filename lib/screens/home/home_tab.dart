import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/feature_map.dart';
import '../../config/motion.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/home_customization_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/animations.dart';
import '../../widgets/floating_nav_padding.dart';
import 'getting_started_card.dart';
import 'home_sections.dart';
import 'today_card.dart';

/// The Home tab body. Discovery is organized into a clear hierarchy:
/// a single compact top bar (avatar + greeting + search), a horizontal strip of
/// customizable Quick Actions (daily use), a row of mini stat pills, then a
/// categorized grid (Orders, Billing, Smart Inventory) sourced from
/// [FeatureMap], so every feature has a single, predictable home.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

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
                8,
                Responsive.horizontalPadding(context),
                24,
              ),
              children: [
                _buildTopBar(context, user.name, initials, user),
                _buildUpdatedLabel(context),
                const SizedBox(height: 10),
                _buildQuickActionsSection(context, perms, isWide),
                const SizedBox(height: 14),
                const QuickStats(),
                const SizedBox(height: 10),
                const TodayCard(),
                const GettingStartedCard(),
                const SizedBox(height: 14),
                const FadeSlideIn(index: 3, child: InsightsCard()),
                const SizedBox(height: 12),
                const _HomeMoreSection(),
                const SizedBox(height: 4),
                ..._buildCategoryGrids(context, perms),
                const SizedBox(height: 16),
                const RecentActivity(),
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
        gradient: AppTheme.heroGradient,
      ),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: Colors.transparent,
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
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
              fontSize: 11,
              color: AppTheme.textTer(context),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Quick Actions (customizable cards) + section header
  // ---------------------------------------------------------------------------
  Widget _buildQuickActionsSection(
    BuildContext context,
    Map<String, bool> perms,
    bool isWide,
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

    if (actions.isEmpty) return const SizedBox.shrink();

    final cards = actions
        .map(
          (action) => HomeActionCard(
            icon: action.icon,
            label: action.label,
            gradient: action.gradient,
            onTap: () => Navigator.pushNamed(context, action.route),
          ),
        )
        .toList();

    Widget grid;
    if (isWide) {
      final spaced =
          cards
              .expand((b) => [Expanded(child: b), const SizedBox(width: 12)])
              .toList()
            ..removeLast();
      grid = Row(children: spaced);
    } else {
      // Horizontal scroll strip keeps primary daily actions above the fold.
      grid = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: Responsive.scrollPhysics(context),
        child: Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              SizedBox(width: 104, child: cards[i]),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Quick Actions',
          padding: EdgeInsets.symmetric(vertical: 4),
        ),
        const SizedBox(height: 8),
        FadeSlideIn(index: 1, child: grid),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Categorized discovery grid (single source of truth via FeatureMap)
  // ---------------------------------------------------------------------------
  List<Widget> _buildCategoryGrids(
    BuildContext context,
    Map<String, bool> perms,
  ) {
    final billingOn = context.watch<BillingSettingsProvider>().billingEnabled;
    final settings = context.watch<SettingsProvider>();

    final categories = FeatureMap.homeGridCategories(
      perms,
      billingEnabled: billingOn,
      barcodeEnabled: settings.barcodeEnabled,
      vendorsEnabled: settings.vendorsEnabled,
      pricingEnabled: settings.pricingEnabled,
    );

    final widgets = <Widget>[];
    for (final category in categories) {
      final entries = FeatureMap.entriesByCategory(
        category,
        perms,
        placement: FeaturePlacement.homeSecondary,
        billingEnabled: billingOn,
        barcodeEnabled: settings.barcodeEnabled,
        vendorsEnabled: settings.vendorsEnabled,
        pricingEnabled: settings.pricingEnabled,
      );
      if (entries.isEmpty) continue;
      final meta = FeatureMap.categoryMeta[category]!;
      final accent = FeatureMap.categoryColor(category);

      widgets.add(const SizedBox(height: 16));
      widgets.add(
        SectionHeader(title: meta.title, subtitle: meta.subtitle),
      );
      widgets.add(const SizedBox(height: 12));
      widgets.add(
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = Responsive.isDesktop(context) ? 4 : 2;
            const spacing = 10.0;
            final cardWidth =
                (constraints.maxWidth - spacing * (cols - 1)) / cols;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: entries
                  .map(
                    (e) => SizedBox(
                      width: cardWidth,
                      child: HomeNavTile(
                        icon: e.icon,
                        label: e.label,
                        subtitle: e.subtitle,
                        color: accent,
                        onTap: () => Navigator.pushNamed(context, e.route),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
    }
    return widgets;
  }
}

/// Tucks the secondary Favorites + Tip-of-the-Day surfaces behind a single
/// "Show more" expander so they don't push primary content below the fold.
/// Honors reduce-motion via the zero-duration [AnimatedCrossFade].
class _HomeMoreSection extends StatefulWidget {
  const _HomeMoreSection();

  @override
  State<_HomeMoreSection> createState() => _HomeMoreSectionState();
}

class _HomeMoreSectionState extends State<_HomeMoreSection> {
  bool _expanded = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    return Column(
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
          secondChild: const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeSlideIn(child: FavoritesSection()),
                SizedBox(height: 16),
                FadeSlideIn(child: TipOfTheDay()),
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
    );
  }
}
