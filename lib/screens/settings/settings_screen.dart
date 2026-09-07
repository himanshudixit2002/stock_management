import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/settings_catalog.dart';
import '../../config/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/home_customization_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/role_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/local_notification_service.dart';
import '../../services/notification_engine.dart';
import '../../utils/dialogs.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_bar_title_row.dart';
import '../../widgets/app_list_row.dart';
import '../../widgets/floating_nav_padding.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/tab_context_header.dart';
import 'manage_list_sheet.dart';
import 'settings_context.dart';
import 'settings_search.dart';
import 'settings_search_field.dart';
import 'settings_summaries.dart';

/// The Settings hub.
///
/// This screen used to render twelve sections and forty-odd destinations on one
/// scroll. Two things were wrong with that. Finding anything meant scrolling
/// past everything; and the rows said only what they were called —
/// "Appearance", "Notifications" — so answering "is dark mode on?" cost a tap
/// and a trip back.
///
/// It is now nine category rows, each carrying its own current state, over a
/// search that indexes every setting in the app rather than only the rows that
/// happen to be on screen. Both the rows and the search read
/// [SettingsCatalog], so a setting appears here exactly when it is findable
/// there.
class SettingsScreen extends StatefulWidget {
  final String? initialSection;
  const SettingsScreen({super.key, this.initialSection});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
    // Deep entry from Stock In / Transfer / Adjustment, which send someone here
    // when a product has no locations to pick from. In initState rather than
    // build: a side effect in build runs again on every rebuild, and only a
    // one-shot bool was stopping it opening the sheet twice.
    final section = widget.initialSection;
    if (section != null && ManageListAction.all.contains(section)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showManageListAction(context, section);
      });
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {
      // The Help row falls back to a static description without it.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Row summaries
  // ---------------------------------------------------------------------------

  /// The live second line for [id].
  ///
  /// This is what makes a hub of nine rows better than a list of forty rather
  /// than merely shorter: the row answers the question without being opened.
  /// Each case reads only the providers its own category depends on, and passes
  /// a `loaded` flag, so a row shows a plain description until its data is real
  /// instead of flashing a default it is about to correct.
  String _summaryFor(SettingsCategoryId id, UserModel user) {
    final settings = context.watch<SettingsProvider>();

    switch (id) {
      case SettingsCategoryId.account:
        // No role here: the profile card shows it as a badge, and appending it
        // to a long email only pushed it past the ellipsis.
        return accountSummary(email: user.email, roleLabel: '');

      case SettingsCategoryId.appearance:
        final home = context.watch<HomeCustomizationProvider>();
        return appearanceSummary(
          mode: context.watch<ThemeProvider>().themeMode,
          quickActionCount: home.selectedIds.length,
          loaded: home.isLoaded,
        );

      case SettingsCategoryId.notifications:
        final prefs = context.watch<NotificationProvider>().prefs;
        return notificationsSummary(
          enabled: prefs.enabledTypes.length,
          total: AlertType.all.length,
          expiryDays: prefs.expiryWarningDays,
          trayAvailable: LocalNotificationService.instance.isSupported,
        );

      case SettingsCategoryId.features:
        return featuresSummary(
          pricing: settings.pricingEnabled,
          vendors: settings.vendorsEnabled,
          barcode: settings.barcodeEnabled,
          billing: context.watch<BillingSettingsProvider>().billingEnabled,
          loaded: settings.isInitialized,
        );

      case SettingsCategoryId.billing:
        final billing = context.watch<BillingSettingsProvider>();
        final b = billing.settings;
        return billingSummary(
          loaded: billing.isInitialized,
          currencySymbol: b.currencySymbol,
          taxLabel: b.taxLabel,
          taxRate: b.defaultTaxRate,
          enableTax: b.enableTax,
          invoicePrefix: b.invoicePrefix,
          nextInvoiceNumber: b.nextInvoiceNumber,
        );

      case SettingsCategoryId.catalog:
        return catalogSummary(
          categories: context.watch<CategoryProvider>().categories.length,
          companies: settings.companies.length,
          subCategories: settings.sizes.length,
          locations: settings.locations.length,
          loaded: settings.isInitialized,
        );

      case SettingsCategoryId.team:
        final roles = context.watch<RoleProvider>().roles;
        return teamSummary(
          roleCount: roles.length,
          rolesLoaded: roles.isNotEmpty,
          canManageUsers: user.hasPermission(AppPermissions.manageUsers),
          vendorsOn: settings.vendorsEnabled,
        );

      case SettingsCategoryId.data:
        return dataSummary(
          canImport: user.hasPermission(AppPermissions.importData),
          canExport: user.hasPermission(AppPermissions.exportData),
          canDataHealth: user.hasPermission(
            AppPermissions.manageCompanySettings,
          ),
        );

      case SettingsCategoryId.plan:
        return planSummary(
          planLabel: settings.plan.label,
          usable: settings.isWorkspaceUsable,
          statusNote: settings.workspaceStatusNote,
          loaded: settings.isInitialized,
        );

      case SettingsCategoryId.help:
        return helpSummary(appVersion: _appVersion);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user == null) return const SizedBox.shrink();

    final ctx = settingsVisibilityContext(context);
    final query = _query.trim();
    final searching = query.isNotEmpty;

    // Only reserve space for the floating nav when this screen is the Settings
    // tab in the shell (no pushed AppBar). When opened as a sub-route there is
    // no floating nav.
    final isTabShell = widget.initialSection == null;
    final navInset = isTabShell ? floatingNavContentInset(context) : 0.0;
    final horizontal = Responsive.horizontalPadding(context);

    final rows = <Widget>[
      for (final (index, category)
          in SettingsCatalog.visibleCategories(ctx).indexed)
        AppListRow(
          key: ValueKey(category.id),
          index: index,
          icon: category.icon,
          accent: category.accent,
          title: category.title,
          subtitle: _summaryFor(category.id, user),
          onTap: () => Navigator.pushNamed(context, category.route),
        ),
    ];

    final body = SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppTheme.spacingMD,
              horizontal,
              40 + navInset,
            ),
            children: [
              // The contextual header is redundant on phones (the tab bar
              // already names the screen) — keep it only on wide/desktop.
              if (isTabShell && Responsive.isWide(context))
                const Padding(
                  padding: EdgeInsets.only(bottom: AppTheme.spacingMD),
                  child: CompactTabHeader(
                    icon: Icons.settings_rounded,
                    title: 'Settings & Account',
                    subtitle: 'Preferences, features, data and your team',
                    initiallyExpanded: true,
                    padding: EdgeInsets.zero,
                  ),
                ),
              _ProfileCard(
                user: user,
                summary: _summaryFor(SettingsCategoryId.account, user),
              ),
              const SizedBox(height: AppTheme.spacingMD),
              SettingsSearchField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
              ),
              if (searching)
                SettingsSearchResults(
                  hits: searchSettings(query, ctx: ctx),
                  query: query,
                  onOpen: (leaf) => openSetting(context, leaf),
                )
              else ...[
                _CategoryRows(rows: rows),
                const SizedBox(height: AppTheme.spacingLG),
                _LogoutButton(onPressed: () => _confirmLogout(context)),
              ],
            ],
          ),
        ),
      ),
    );

    // The same gradient ground on both paths. This screen renders either as a
    // shell tab or as a pushed sub-route, and only the pushed one used to get
    // the gradient — so Settings looked different depending on how you reached
    // it.
    final grounded = Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: body,
    );

    if (!isTabShell) {
      return Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(
          title: AppBarTitleRow(
            icon: Icons.settings_rounded,
            color: AppTheme.primary(context),
            title: 'Settings',
          ),
        ),
        body: grounded,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Was SystemUiOverlayStyle.light/.dark, whose presets carry an opaque black
    // systemNavigationBarColor -- that painted a black gesture bar on this
    // screen alone while every other screen stayed transparent.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.systemBars(isDark),
      child: grounded,
    );
  }

  void _confirmLogout(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Logout',
      message: 'Are you sure you want to logout?',
      confirmLabel: 'Logout',
      icon: Icons.logout_rounded,
    );
    if (confirmed && context.mounted) {
      await context.read<AuthProvider>().logout();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }
}

/// The category rows: one column on phones, two on a wide desktop.
///
/// The old screen packed its sections into two to four masonry columns using a
/// hand-written table of estimated heights keyed on the section *title*, which
/// silently mis-balanced the moment a section was renamed or gated off. The
/// rows are uniform now, so an even split needs no estimate at all.
class _CategoryRows extends StatelessWidget {
  const _CategoryRows({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    if (!kIsWeb || !Responsive.isDesktop(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }
    final split = (rows.length / 2).ceil();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rows.sublist(0, split),
          ),
        ),
        const SizedBox(width: AppTheme.spacingMD),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rows.sublist(split),
          ),
        ),
      ],
    );
  }
}

/// The signed-in user, and the way into their account.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.summary});

  final UserModel user;
  final String summary;

  String get _initials {
    final name = user.name.trim();
    if (name.isEmpty) return '?';
    return name
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: AppTheme.radiusMD,
      useContentVariant: true,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            // The full account screen, rather than the three bottom sheets
            // Settings used to carry its own copies of.
            onTap: () => Navigator.pushNamed(context, AppRoutes.profile),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLG,
                vertical: AppTheme.spacingMD,
              ),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.heroGrad(context),
                    ),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.transparent,
                      child: Text(
                        _initials,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.onGradient,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingMD),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.name.trim().isEmpty ? 'Your account' : user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textSec(context)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSM),
                  _RoleBadge(user: user),
                  const SizedBox(width: AppTheme.spacingXS),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppTheme.iconMute(context),
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

/// The signed-in user's role, as a pill.
///
/// A badge rather than another clause on the summary line: appended to a long
/// email it was the first thing the ellipsis ate.
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.primary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.tint(context, color),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        user.isAdmin ? 'ADMIN' : user.role.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final btn = Container(
      decoration: BoxDecoration(
        gradient: AppTheme.dangerGrad(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        boxShadow: AppTheme.coloredShadow(AppTheme.dangerColor),
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: const Text(
          'Logout',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: AppTheme.surface(context),
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    );
    if (!Responsive.isDesktop(context)) return btn;
    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: btn,
      ),
    );
  }
}
