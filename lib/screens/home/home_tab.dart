import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config/feature_map.dart';
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
import 'home_sections.dart';

/// The Home tab body. Discovery is organized into a clear hierarchy:
/// a small set of customizable Quick Action cards (daily use) followed by a
/// categorized grid (Orders, Billing, Smart Inventory) sourced from
/// [FeatureMap], so every feature has a single, predictable home.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

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
                12,
                Responsive.horizontalPadding(context),
                24,
              ),
              children: [
                _buildSearchRow(context),
                _buildUpdatedLabel(context),
                const SizedBox(height: 4),
                FadeSlideIn(
                  index: 0,
                  child: _buildProfileHero(context, user, initials),
                ),
                const SizedBox(height: 16),
                _buildQuickActionsSection(context, perms, isWide),
                const SizedBox(height: 16),
                const QuickStats(),
                const SizedBox(height: 16),
                const FadeSlideIn(index: 3, child: InsightsCard()),
                const SizedBox(height: 16),
                const FadeSlideIn(index: 4, child: FavoritesSection()),
                const SizedBox(height: 16),
                const FadeSlideIn(index: 5, child: TipOfTheDay()),
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
  // Search + notifications row
  // ---------------------------------------------------------------------------
  Widget _buildSearchRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.inputBorder(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.globalSearch),
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
  // Profile hero
  // ---------------------------------------------------------------------------
  Widget _buildProfileHero(
    BuildContext context,
    UserModel user,
    String initials,
  ) {
    return Container(
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
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          ),
                          if (user.companyMemberships.length > 1) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.swap_horiz_rounded,
                              size: 16,
                              color: Colors.white.withValues(alpha: 0.7),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
      grid = LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: cards
                .map((b) => SizedBox(width: itemWidth, child: b))
                .toList(),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Quick Actions',
          subtitle: 'Your most-used daily tasks — tap + below for more',
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
