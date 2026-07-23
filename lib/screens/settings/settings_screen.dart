import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../utils/url_helper.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/settings_provider.dart';
import '../../config/permissions.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../providers/theme_provider.dart';
import '../../providers/billing_settings_provider.dart';
import '../../utils/responsive.dart';
import '../../utils/dialogs.dart';
import '../../config/motion.dart';
import '../../widgets/animations.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/floating_nav_padding.dart';
import '../../widgets/tab_context_header.dart';

class SettingsScreen extends StatefulWidget {
  final String? initialSection;
  const SettingsScreen({super.key, this.initialSection});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _didAutoOpen = false;

  bool _settingsWebLux(BuildContext context) =>
      kIsWeb && Responsive.isDesktop(context);

  double _settingsSectionGap(BuildContext context) =>
      _settingsWebLux(context) ? 16 : 12;

  Widget _buildSettingsContextHeader(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: CompactTabHeader(
        icon: Icons.settings_rounded,
        title: 'Settings & Account',
        subtitle: 'Preferences, features, data and your team',
        initiallyExpanded: true,
        padding: EdgeInsets.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_didAutoOpen && widget.initialSection == 'locations') {
      _didAutoOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showManageListDialog(
            context,
            title: 'Manage Locations',
            icon: Icons.location_on_rounded,
            getItems: () => context.read<SettingsProvider>().locations,
            onAdd: (name) => context.read<SettingsProvider>().addLocation(name),
            onRemove: (name) =>
                context.read<SettingsProvider>().removeLocation(name),
            onRename: (oldName, newName) => context
                .read<SettingsProvider>()
                .renameLocation(oldName, newName),
            addLabel: 'location',
          );
        }
      });
    }
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

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

    final viewPadding = MediaQuery.paddingOf(context);
    // Only reserve space for the floating nav when this screen is the Settings
    // tab in the shell (no pushed AppBar). When opened as a sub-route
    // (initialSection != null) there is no floating nav.
    final isTabShell = widget.initialSection == null;
    final navInset = isTabShell ? floatingNavContentInset(context) : 0.0;
    final padding = EdgeInsets.fromLTRB(
      Responsive.horizontalPadding(context),
      _settingsWebLux(context) ? 20 : 12,
      Responsive.horizontalPadding(context),
      (_settingsWebLux(context)
              ? (viewPadding.bottom > 0 ? viewPadding.bottom + 4 : 8)
              : 40) +
          navInset,
    );
    final webGrid = _settingsWebLux(context);
    final sectionBlocks = _buildSettingsSectionBlocks(context, user);

    final body = SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: webGrid
              ? SingleChildScrollView(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isTabShell) _buildSettingsContextHeader(context),
                      _buildSettingsProfileCard(context, user, initials),
                      SizedBox(height: _settingsSectionGap(context)),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return _buildWebSettingsSectionColumns(
                            context,
                            sectionBlocks,
                            constraints.maxWidth,
                          );
                        },
                      ),
                      SizedBox(height: _settingsWebLux(context) ? 0 : 20),
                      _buildSettingsLogoutButton(
                        context,
                        useNarrowLuxLogout: false,
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: padding,
                  children: [
                    // The contextual header is redundant on phones (the tab
                    // bar already names the screen) — keep it only on wide/
                    // desktop layouts.
                    if (isTabShell && Responsive.isWide(context))
                      _buildSettingsContextHeader(context),
                    _buildSettingsProfileCard(context, user, initials),
                    SizedBox(height: _settingsSectionGap(context)),
                    ..._interleaveSettingsSectionGaps(context, sectionBlocks),
                    SizedBox(height: _settingsWebLux(context) ? 0 : 20),
                    _buildSettingsLogoutButton(context),
                  ],
                ),
        ),
      ),
    );

    if (widget.initialSection != null) {
      return Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(title: const Text('Settings')),
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
          child: body,
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            ),
      child: body,
    );
  }

  EdgeInsets _settingsSwitchContentPadding(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal: _settingsWebLux(context) ? 18 : 12,
      vertical: 0,
    );
  }

  List<Widget> _interleaveSettingsSectionGaps(
    BuildContext context,
    List<Widget> sections,
  ) {
    if (sections.isEmpty) return [];
    final gap = _settingsSectionGap(context);
    final out = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) out.add(SizedBox(height: gap));
      out.add(FadeSlideIn(index: i, child: sections[i]));
    }
    return out;
  }

  /// Rough relative heights for balancing columns (greedy shortest-column).
  int _webSettingsSectionLayoutWeight(Widget w) {
    if (w is! _SettingsSectionBlock) return 2;
    switch (w.title) {
      case 'Features':
      case 'Administration':
        return 6;
      case 'Product Attributes':
      case 'Advanced':
      case 'Legal':
        return 4;
      case 'Account':
      case 'Data':
        return 3;
      case 'Appearance':
      case 'Home Page':
      case 'Tools':
        return 1;
      default:
        return 2;
    }
  }

  /// Top-aligned columns; greedy placement by estimated height for smoother
  /// bottoms than [Wrap] row gaps or naive round-robin.
  Widget _buildWebSettingsSectionColumns(
    BuildContext context,
    List<Widget> sections,
    double maxWidth,
  ) {
    if (sections.isEmpty) return const SizedBox.shrink();

    const columnGap = 10.0;
    const verticalGap = 10.0;

    final maxCols = (maxWidth / 280).floor().clamp(2, 4);
    final n = sections.length < maxCols ? sections.length : maxCols;

    final columns = List.generate(n, (_) => <Widget>[]);
    final load = List.filled(n, 0);
    for (final s in sections) {
      var bestCol = 0;
      var bestLoad = load[0];
      for (var c = 1; c < n; c++) {
        if (load[c] < bestLoad) {
          bestLoad = load[c];
          bestCol = c;
        }
      }
      columns[bestCol].add(s);
      load[bestCol] += _webSettingsSectionLayoutWeight(s);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var ci = 0; ci < n; ci++) ...[
          if (ci > 0) const SizedBox(width: columnGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var j = 0; j < columns[ci].length; j++) ...[
                  if (j > 0) const SizedBox(height: verticalGap),
                  columns[ci][j],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSettingsProfileCard(
    BuildContext context,
    UserModel user,
    String initials,
  ) {
    // On phones the full gradient hero is overkill — show a compact row that
    // links to Edit Profile. The hero styling is reserved for wide/desktop.
    if (!Responsive.isWide(context)) {
      return _buildCompactProfileRow(context, user, initials);
    }
    return Container(
      padding: EdgeInsets.all(_settingsWebLux(context) ? 20 : 10),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(_settingsWebLux(context) ? 20 : 14),
        boxShadow: AppTheme.coloredShadow(AppTheme.primaryColor),
        border: _settingsWebLux(context)
            ? Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1)
            : null,
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: _settingsWebLux(context) ? 3 : 2,
              ),
              boxShadow: _settingsWebLux(context)
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: CircleAvatar(
              radius: _settingsWebLux(context) ? 30 : 22,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: _settingsWebLux(context) ? 20 : 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.onGradient,
                ),
              ),
            ),
          ),
          SizedBox(width: _settingsWebLux(context) ? 18 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: TextStyle(
                    fontSize: _settingsWebLux(context) ? 20 : 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.onGradient,
                    letterSpacing: _settingsWebLux(context) ? -0.3 : 0,
                  ),
                ),
                SizedBox(height: _settingsWebLux(context) ? 4 : 1),
                Text(
                  user.email,
                  style: TextStyle(
                    fontSize: _settingsWebLux(context) ? 13 : 12,
                    color: AppTheme.onGradientMuted,
                  ),
                ),
                if (user.companyName.isNotEmpty) ...[
                  SizedBox(height: _settingsWebLux(context) ? 6 : 2),
                  Text(
                    user.companyName,
                    style: TextStyle(
                      fontSize: _settingsWebLux(context) ? 14 : 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.onGradient,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _settingsWebLux(context) ? 14 : 10,
              vertical: _settingsWebLux(context) ? 8 : 4,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Text(
              user.isAdmin ? 'ADMIN' : user.role.toUpperCase(),
              style: TextStyle(
                fontSize: _settingsWebLux(context) ? 12 : 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.onGradient,
                letterSpacing: 0.9,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactProfileRow(
    BuildContext context,
    UserModel user,
    String initials,
  ) {
    return GlassPanel(
      borderRadius: 14,
      useContentVariant: true,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showEditProfileDialog(context),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  decoration: const BoxDecoration(
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPri(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        user.email,
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
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    user.isAdmin ? 'ADMIN' : user.role.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
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
    );
  }

  List<Widget> _buildSettingsSectionBlocks(
    BuildContext context,
    UserModel user,
  ) {
    return [
      _SettingsSectionBlock(
        title: 'Appearance',
        accentColor: AppTheme.accentColor,
        children: [
          Builder(
            builder: (context) {
              final lux = kIsWeb && Responsive.isDesktop(context);
              final segIcon = lux ? 18.0 : 16.0;
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: lux ? 18 : 12,
                  vertical: lux ? 14 : 8,
                ),
                child: Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) => Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(lux ? 8 : 5),
                        decoration: BoxDecoration(
                          color: AppTheme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(lux ? 12 : 8),
                        ),
                        child: Icon(
                          Icons.palette_rounded,
                          color: AppTheme.accentColor,
                          size: lux ? 24 : 20,
                        ),
                      ),
                      SizedBox(width: lux ? 14 : 10),
                      Text(
                        'Theme',
                        style: TextStyle(
                          fontSize: lux ? 16 : 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const Spacer(),
                      SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto, size: segIcon),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode, size: segIcon),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode, size: segIcon),
                          ),
                        ],
                        selected: {themeProvider.themeMode},
                        onSelectionChanged: (modes) =>
                            themeProvider.setThemeMode(modes.first),
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          visualDensity: lux
                              ? VisualDensity.standard
                              : VisualDensity.compact,
                          tapTargetSize: lux
                              ? MaterialTapTargetSize.padded
                              : MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      _SettingsSectionBlock(
        title: 'Home Page',
        accentColor: AppTheme.successColor,
        children: [
          _SettingsTile(
            icon: Icons.dashboard_customize_rounded,
            iconColor: AppTheme.successColor,
            title: 'Customize Home Actions',
            subtitle: 'Choose up to 6 quick actions for your home screen',
            onTap: () =>
                Navigator.pushNamed(context, AppRoutes.homeCustomization),
          ),
        ],
      ),
      _SettingsSectionBlock(
        title: 'Account',
        accentColor: AppTheme.primaryColor,
        children: [
          _SettingsTile(
            icon: Icons.person_rounded,
            iconColor: AppTheme.primaryColor,
            title: 'Edit Profile',
            subtitle: 'Update your name and phone',
            onTap: () => _showEditProfileDialog(context),
          ),
          const Divider(height: 1, indent: 48),
          _SettingsTile(
            icon: Icons.lock_reset_rounded,
            iconColor: AppTheme.indigoColor,
            title: 'Change Password',
            onTap: () => _showChangePasswordDialog(context),
          ),
          const Divider(height: 1, indent: 48),
          _SettingsTile(
            icon: Icons.delete_forever_rounded,
            iconColor: AppTheme.dangerColor,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account and data',
            onTap: () => _showDeleteAccountDialog(context),
          ),
        ],
      ),
      if (user.isAdmin) ...[
        _SettingsSectionBlock(
          title: 'Features',
          accentColor: AppTheme.infoColor,
          children: [
            Consumer<SettingsProvider>(
              builder: (context, settings, _) => SwitchListTile(
                dense: true,
                secondary: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppTheme.successColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.attach_money_rounded,
                    color: AppTheme.successColor,
                    size: 18,
                  ),
                ),
                title: const Text(
                  'Enable Pricing',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Show cost & selling price on products',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTer(context),
                  ),
                ),
                value: settings.pricingEnabled,
                activeTrackColor: AppTheme.successColor,
                onChanged: (val) async {
                  final success = await settings.togglePricing(val);
                  if (!success && context.mounted) {
                    showErrorSnackBar(
                      context,
                      settings.errorMessage ?? 'Failed to update setting',
                    );
                  }
                },
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
              ),
            ),
            const Divider(height: 1, indent: 48),
            Consumer<SettingsProvider>(
              builder: (context, settings, _) => SwitchListTile(
                dense: true,
                secondary: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppTheme.indigoColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_shipping_rounded,
                    color: AppTheme.indigoColor,
                    size: 18,
                  ),
                ),
                title: const Text(
                  'Enable Vendors',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Track vendor assignments & costs',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTer(context),
                  ),
                ),
                value: settings.vendorsEnabled,
                activeTrackColor: AppTheme.indigoColor,
                onChanged: (val) async {
                  final success = await settings.toggleVendors(val);
                  if (!success && context.mounted) {
                    showErrorSnackBar(
                      context,
                      settings.errorMessage ?? 'Failed to update setting',
                    );
                  }
                },
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
              ),
            ),
            const Divider(height: 1, indent: 48),
            Consumer<SettingsProvider>(
              builder: (context, settings, _) => SwitchListTile(
                dense: true,
                secondary: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner,
                    color: AppTheme.warningColor,
                    size: 18,
                  ),
                ),
                title: const Text(
                  'Enable Barcode Scanner',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Scan & manage product barcodes',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTer(context),
                  ),
                ),
                value: settings.barcodeEnabled,
                activeTrackColor: AppTheme.warningColor,
                onChanged: (val) async {
                  final success = await settings.toggleBarcode(val);
                  if (!success && context.mounted) {
                    showErrorSnackBar(
                      context,
                      settings.errorMessage ?? 'Failed to update setting',
                    );
                  }
                },
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
              ),
            ),
            const Divider(height: 1, indent: 48),
            Builder(
              builder: (context) {
                final billingSettings = context
                    .watch<BillingSettingsProvider>();
                return SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppTheme.successColor,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Enable Billing',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'Invoicing, payments & PDF bills',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textTer(context),
                    ),
                  ),
                  value: billingSettings.billingEnabled,
                  activeTrackColor: AppTheme.successColor,
                  onChanged: (val) async {
                    final success = await billingSettings.toggleBilling(val);
                    if (!success && context.mounted) {
                      showErrorSnackBar(
                        context,
                        billingSettings.errorMessage ??
                            'Failed to update setting',
                      );
                    }
                  },
                  contentPadding: _settingsSwitchContentPadding(context),
                );
              },
            ),
          ],
        ),
        _SettingsSectionBlock(
          title: 'Product Attributes',
          accentColor: AppTheme.accentColor,
          children: [
            _SettingsTile(
              icon: Icons.category_rounded,
              iconColor: AppTheme.indigoColor,
              title: 'Manage Categories',
              subtitle: 'Organize products by category',
              onTap: () => Navigator.pushNamed(context, AppRoutes.categories),
            ),
            const Divider(height: 1, indent: 48),
            _SettingsTile(
              icon: Icons.business_rounded,
              iconColor: AppTheme.primaryColor,
              title: 'Manage Companies',
              subtitle: 'Add or remove product brands/companies',
              onTap: () => _showManageListDialog(
                context,
                title: 'Manage Companies',
                icon: Icons.business_rounded,
                getItems: () => context.read<SettingsProvider>().companies,
                onAdd: (name) =>
                    context.read<SettingsProvider>().addCompany(name),
                onRemove: (name) =>
                    context.read<SettingsProvider>().removeCompany(name),
                onRename: (oldName, newName) async {
                  final ok = await context
                      .read<SettingsProvider>()
                      .renameCompany(oldName, newName);
                  if (ok) context.read<ProductProvider>().refreshProducts();
                  return ok;
                },
                addLabel: 'company',
              ),
            ),
            const Divider(height: 1, indent: 48),
            _SettingsTile(
              icon: Icons.label_rounded,
              iconColor: AppTheme.infoColor,
              title: 'Manage Sub-Categories',
              subtitle: 'Add or remove product sub-categories',
              onTap: () => _showManageListDialog(
                context,
                title: 'Manage Sub-Categories',
                icon: Icons.label_rounded,
                getItems: () => context.read<SettingsProvider>().sizes,
                onAdd: (name) => context.read<SettingsProvider>().addSize(name),
                onRemove: (name) =>
                    context.read<SettingsProvider>().removeSize(name),
                onRename: (oldName, newName) async {
                  final ok = await context.read<SettingsProvider>().renameSize(
                    oldName,
                    newName,
                  );
                  if (ok) context.read<ProductProvider>().refreshProducts();
                  return ok;
                },
                addLabel: 'sub-category',
              ),
            ),
            const Divider(height: 1, indent: 48),
            _SettingsTile(
              icon: Icons.location_on_rounded,
              iconColor: AppTheme.warningColor,
              title: 'Manage Locations',
              subtitle: 'Add or remove stock locations',
              onTap: () => _showManageListDialog(
                context,
                title: 'Manage Locations',
                icon: Icons.location_on_rounded,
                getItems: () => context.read<SettingsProvider>().locations,
                onAdd: (name) =>
                    context.read<SettingsProvider>().addLocation(name),
                onRemove: (name) =>
                    context.read<SettingsProvider>().removeLocation(name),
                onRename: (oldName, newName) async {
                  final ok = await context
                      .read<SettingsProvider>()
                      .renameLocation(oldName, newName);
                  if (ok) context.read<ProductProvider>().refreshProducts();
                  return ok;
                },
                addLabel: 'location',
              ),
            ),
          ],
        ),
        _SettingsSectionBlock(
          title: 'Administration',
          accentColor: AppTheme.warningColor,
          children: [
            _SettingsTile(
              icon: Icons.receipt_long_rounded,
              iconColor: AppTheme.successColor,
              title: 'Billing Settings',
              subtitle: 'Company profile, tax, numbering & terms',
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.billingSettings),
            ),
            const Divider(height: 1, indent: 48),
            if (user.hasPermission(AppPermissions.manageUsers)) ...[
              _SettingsTile(
                icon: Icons.people_rounded,
                iconColor: AppTheme.infoColor,
                title: 'User Management',
                subtitle: 'Add and manage staff users',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.userManagement),
              ),
              const Divider(height: 1, indent: 48),
            ],
            if (user.hasPermission(AppPermissions.manageRoles)) ...[
              _SettingsTile(
                icon: Icons.admin_panel_settings_rounded,
                iconColor: AppTheme.primaryColor,
                title: 'Roles & Permissions',
                subtitle: 'Create and manage roles with granular permissions',
                onTap: () => Navigator.pushNamed(context, AppRoutes.roles),
              ),
              const Divider(height: 1, indent: 48),
            ],
            if (user.hasPermission(AppPermissions.manageUsers)) ...[
              _SettingsTile(
                icon: Icons.shield_rounded,
                iconColor: AppTheme.warningColor,
                title: 'Permission Overrides',
                subtitle: 'Per-user permission exceptions',
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.staffPermissions),
              ),
            ],
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
                if (!settings.vendorsEnabled) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    const Divider(height: 1, indent: 48),
                    _SettingsTile(
                      icon: Icons.local_shipping_rounded,
                      iconColor: AppTheme.indigoColor,
                      title: 'Manage Vendors',
                      subtitle: 'Add, edit and track vendor performance',
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.vendors),
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 1, indent: 48),
            _SettingsTile(
              icon: Icons.people_alt_rounded,
              iconColor: AppTheme.primaryColor,
              title: 'Manage Customers',
              subtitle: 'View and manage your customers',
              onTap: () => Navigator.pushNamed(context, AppRoutes.customers),
            ),
          ],
        ),
      ],
      _SettingsSectionBlock(
        title: 'Data',
        accentColor: AppTheme.successColor,
        children: [
          _SettingsTile(
            icon: Icons.file_upload_rounded,
            iconColor: AppTheme.infoColor,
            title: 'Import Data',
            onTap: () => Navigator.pushNamed(context, AppRoutes.excelImport),
          ),
          const Divider(height: 1, indent: 48),
          _SettingsTile(
            icon: Icons.file_download_rounded,
            iconColor: AppTheme.successColor,
            title: 'Export Data',
            onTap: () => Navigator.pushNamed(context, AppRoutes.excelExport),
          ),
        ],
      ),
      _SettingsSectionBlock(
        title: 'Advanced',
        accentColor: AppTheme.indigoColor,
        children: [
          _SettingsTile(
            icon: Icons.warehouse_rounded,
            iconColor: AppTheme.warningColor,
            title: 'Warehouse Zones',
            subtitle: 'Manage storage zones and areas',
            onTap: () => Navigator.pushNamed(context, AppRoutes.warehouseZones),
          ),
          const Divider(height: 1, indent: 48),
          _SettingsTile(
            icon: Icons.inventory_2_rounded,
            iconColor: AppTheme.successColor,
            title: 'Bulk Stock In',
            subtitle: 'Add stock for multiple products at once',
            onTap: () => Navigator.pushNamed(context, AppRoutes.bulkStockIn),
          ),
          const Divider(height: 1, indent: 48),
          _SettingsTile(
            icon: Icons.edit_note_rounded,
            iconColor: AppTheme.infoColor,
            title: 'Bulk Edit',
            subtitle: 'Edit multiple products simultaneously',
            onTap: () => Navigator.pushNamed(context, AppRoutes.bulkEdit),
          ),
          const Divider(height: 1, indent: 48),
          _SettingsTile(
            icon: Icons.swap_horiz_rounded,
            iconColor: AppTheme.primaryColor,
            title: 'Company Switcher',
            subtitle: 'Switch between companies',
            onTap: () =>
                Navigator.pushNamed(context, AppRoutes.companySwitcher),
          ),
        ],
      ),
      _SettingsSectionBlock(
        title: 'Tools',
        accentColor: AppTheme.accentColor,
        children: [
          _SettingsTile(
            icon: Icons.rocket_launch_rounded,
            iconColor: AppTheme.primaryColor,
            title: 'Onboarding Wizard',
            subtitle: 'Re-run the setup wizard',
            onTap: () => Navigator.pushNamed(context, AppRoutes.onboarding),
          ),
        ],
      ),
      _SettingsSectionBlock(
        title: 'Help & About',
        accentColor: AppTheme.infoColor,
        children: [
          _SettingsTile(
            icon: Icons.help_outline_rounded,
            iconColor: AppTheme.primaryColor,
            title: 'Help & Support',
            subtitle: 'Guides, FAQs and send feedback',
            onTap: () => Navigator.pushNamed(context, AppRoutes.help),
          ),
          if (user.hasPermission(AppPermissions.viewActivityTimeline)) ...[
            const Divider(height: 1, indent: 48),
            _SettingsTile(
              icon: Icons.timeline_rounded,
              iconColor: AppTheme.indigoColor,
              title: 'Activity Timeline',
              subtitle: 'A chronological feed of recent activity',
              onTap: () =>
                  Navigator.pushNamed(context, AppRoutes.activityTimeline),
            ),
          ],
          const Divider(height: 1, indent: 48),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            iconColor: AppTheme.textSec(context),
            title: 'About',
            subtitle: 'App version, credits and links',
            onTap: () => Navigator.pushNamed(context, AppRoutes.about),
          ),
        ],
      ),
      _SettingsSectionBlock(
        title: 'Legal',
        accentColor: AppTheme.textSec(context),
        children: [
          _SettingsTile(
            icon: Icons.privacy_tip_rounded,
            iconColor: AppTheme.primaryColor,
            title: 'Privacy Policy',
            onTap: () {
              if (kIsWeb) {
                _launchUrl(
                  context,
                  'https://smartshelfkart.com/privacy-policy.html',
                );
              } else {
                Navigator.pushNamed(context, AppRoutes.privacyPolicy);
              }
            },
          ),
          const Divider(height: 1, indent: 48),
          _SettingsTile(
            icon: Icons.description_rounded,
            iconColor: AppTheme.indigoColor,
            title: 'Terms of Service',
            onTap: () {
              if (kIsWeb) {
                _launchUrl(context, 'https://smartshelfkart.com/terms.html');
              } else {
                Navigator.pushNamed(context, AppRoutes.terms);
              }
            },
          ),
          const Divider(height: 1, indent: 48),
          _SettingsTile(
            icon: Icons.support_agent_rounded,
            iconColor: AppTheme.accentColor,
            title: 'Support',
            onTap: () {
              if (kIsWeb) {
                _launchUrl(context, 'https://smartshelfkart.com/support.html');
              } else {
                Navigator.pushNamed(context, AppRoutes.support);
              }
            },
          ),
          const Divider(height: 1, indent: 48),
          _SettingsTile(
            icon: Icons.delete_sweep_rounded,
            iconColor: AppTheme.dangerColor,
            title: 'Data Deletion',
            onTap: () {
              if (kIsWeb) {
                _launchUrl(
                  context,
                  'https://smartshelfkart.com/data-deletion.html',
                );
              } else {
                Navigator.pushNamed(context, AppRoutes.dataDeletion);
              }
            },
          ),
        ],
      ),
    ];
  }

  Widget _buildSettingsLogoutButton(
    BuildContext context, {
    bool useNarrowLuxLogout = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Builder(
          builder: (context) {
            final lux = _settingsWebLux(context);
            final btn = Container(
              decoration: BoxDecoration(
                gradient: AppTheme.dangerGradient,
                borderRadius: BorderRadius.circular(lux ? 16 : 14),
                boxShadow: AppTheme.coloredShadow(AppTheme.dangerColor),
              ),
              child: ElevatedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: Icon(Icons.logout_rounded, size: lux ? 22 : 20),
                label: Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: lux ? 16 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: AppTheme.surface(context),
                  minimumSize: Size(double.infinity, lux ? 52 : 48),
                ),
              ),
            );
            if (!lux) return btn;
            if (!useNarrowLuxLogout) return btn;
            return Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: btn,
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _launchUrl(BuildContext context, String url) =>
      openUrl(context, url);

  static String _newLabel(String addLabel) {
    if (addLabel.isEmpty) return 'New item';
    final s = addLabel.trim();
    return 'New ${s[0].toUpperCase()}${s.length > 1 ? s.substring(1) : ''} name';
  }

  static String _listHeading(String addLabel, int count) {
    if (addLabel.isEmpty) return 'Current list ($count)';
    final s = addLabel.trim().toLowerCase();
    final plural = s == 'company'
        ? 'companies'
        : s == 'location'
        ? 'locations'
        : s == 'category'
        ? 'categories'
        : s.endsWith('s')
        ? '${s}es'
        : '${s}s';
    final cap = '${plural[0].toUpperCase()}${plural.substring(1)}';
    return 'Your $cap ($count)';
  }

  void _showManageListDialog(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> Function() getItems,
    required Future<bool> Function(String) onAdd,
    required Future<bool> Function(String) onRemove,
    Future<bool> Function(String oldName, String newName)? onRename,
    String addLabel = '',
  }) {
    final textCtrl = TextEditingController();
    final focusNode = FocusNode();
    final sheetController = DraggableScrollableController();

    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => MediaQuery.removeViewInsets(
        removeBottom: true,
        context: sheetCtx,
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            final items = getItems();
            String? errorText;

            Future<void> handleAdd() async {
              final name = textCtrl.text.trim();
              if (name.isEmpty) return;
              final ok = await onAdd(name);
              if (ok) {
                textCtrl.clear();
                HapticFeedback.lightImpact();
                setSheetState(() {});
                focusNode.requestFocus();
              } else {
                setSheetState(() => errorText = '\'$name\' already exists');
              }
            }

            return DraggableScrollableSheet(
              controller: sheetController,
              initialChildSize: 0.7,
              minChildSize: 0.35,
              maxChildSize: 0.95,
              snap: true,
              snapSizes: const [0.7, 0.95],
              builder: (sheetContext, scrollController) {
                final keyboardHeight = MediaQuery.of(
                  sheetCtx,
                ).viewInsets.bottom;
                if (keyboardHeight > 0 && sheetController.isAttached) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (sheetController.isAttached &&
                        sheetController.size < 0.9) {
                      sheetController.animateTo(
                        0.95,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  });
                }
                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bg(context),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 6, bottom: 2),
                          width: 32,
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppTheme.dividerStrongC(context),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                icon,
                                color: AppTheme.primaryColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPri(context),
                                    ),
                                  ),
                                  Text(
                                    '${items.length} item${items.length == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSec(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetCtx),
                              iconSize: 20,
                              icon: Icon(
                                Icons.close_rounded,
                                color: AppTheme.textSec(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _newLabel(addLabel),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSec(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
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
                                    child: TextField(
                                      controller: textCtrl,
                                      focusNode: focusNode,
                                      decoration: const InputDecoration(
                                        hintText: 'Enter name',
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.fromLTRB(
                                          12,
                                          10,
                                          8,
                                          10,
                                        ),
                                        isDense: true,
                                      ),
                                      textCapitalization:
                                          TextCapitalization.words,
                                      onChanged: (_) {
                                        if (errorText != null) {
                                          setSheetState(() => errorText = null);
                                        }
                                      },
                                      onSubmitted: (_) => handleAdd(),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: 6,
                                      top: 4,
                                      bottom: 4,
                                    ),
                                    child: OutlinedButton(
                                      onPressed: handleAdd,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        minimumSize: const Size(0, 36),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      child: const Text('Add'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (errorText != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  errorText!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.dangerColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _listHeading(addLabel, items.length),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSec(context),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: items.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      icon,
                                      size: 40,
                                      color: AppTheme.emptyIcon(
                                        context,
                                      ).withValues(alpha: 0.3),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'No items yet',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSec(context),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Add one above',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSec(
                                          context,
                                        ).withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding: EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  bottom: keyboardHeight + 16,
                                ),
                                itemCount: items.length,
                                itemBuilder: (_, i) {
                                  final renameCb = onRename;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _ManageListItem(
                                      name: items[i],
                                      onEdit: renameCb != null
                                          ? () => _showRenameDialog(
                                              ctx,
                                              title: title,
                                              currentName: items[i],
                                              onRename: renameCb,
                                              onSuccess: () {
                                                setSheetState(() {});
                                              },
                                            )
                                          : null,
                                      onRemove: () async {
                                        final confirmed =
                                            await _showRemoveConfirmation(
                                              ctx,
                                              items[i],
                                            );
                                        if (confirmed) {
                                          await onRemove(items[i]);
                                          HapticFeedback.lightImpact();
                                          setSheetState(() {});
                                        }
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context, {
    required String title,
    required String currentName,
    required Future<bool> Function(String oldName, String newName) onRename,
    required VoidCallback onSuccess,
  }) async {
    final nameCtrl = TextEditingController(text: currentName);
    nameCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: currentName.length,
    );
    String? errorText;
    var isLoading = false;

    await showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              decoration: BoxDecoration(
                color: AppTheme.surface(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Rename',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'New name will update everywhere (products, transactions).',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    enabled: !isLoading,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: currentName,
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) async {
                      if (isLoading) return;
                      final newName = nameCtrl.text.trim();
                      if (newName.isEmpty) {
                        setState(() => errorText = 'Enter a name');
                        return;
                      }
                      if (newName == currentName) {
                        Navigator.pop(ctx);
                        return;
                      }
                      setState(() {
                        errorText = null;
                        isLoading = true;
                      });
                      final ok = await onRename(currentName, newName);
                      if (!ctx.mounted) return;
                      setState(() => isLoading = false);
                      if (ok) {
                        Navigator.pop(ctx);
                        onSuccess();
                      } else {
                        final msg =
                            context.read<SettingsProvider>().errorMessage ??
                            'Name already exists or rename failed.';
                        setState(() => errorText = msg);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isLoading
                              ? null
                              : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: BorderSide(
                              color: AppTheme.dividerStrongC(context),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isLoading
                              ? null
                              : () async {
                                  final newName = nameCtrl.text.trim();
                                  if (newName.isEmpty) {
                                    setState(() => errorText = 'Enter a name');
                                    return;
                                  }
                                  if (newName == currentName) {
                                    Navigator.pop(ctx);
                                    return;
                                  }
                                  setState(() {
                                    errorText = null;
                                    isLoading = true;
                                  });
                                  final ok = await onRename(
                                    currentName,
                                    newName,
                                  );
                                  if (!ctx.mounted) return;
                                  setState(() => isLoading = false);
                                  if (ok) {
                                    Navigator.pop(ctx);
                                    onSuccess();
                                  } else {
                                    final msg =
                                        context
                                            .read<SettingsProvider>()
                                            .errorMessage ??
                                        'Name already exists or rename failed.';
                                    setState(() => errorText = msg);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isLoading
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primaryColor,
                                  ),
                                )
                              : const Text('Rename'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _showRemoveConfirmation(
    BuildContext context,
    String itemName,
  ) async {
    return await showModalBottomSheet<bool>(
          context: context,
          constraints: Responsive.sheetConstraints(context),
          backgroundColor: Colors.transparent,
          builder: (ctx) => Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            decoration: BoxDecoration(
              color: AppTheme.surface(context),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppTheme.dangerColor,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Remove "$itemName"?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPri(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Existing products with this value won\'t be affected.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSec(context),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                            color: AppTheme.dividerStrongC(context),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: AppTheme.textSec(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.dangerColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Remove',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ) ??
        false;
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

  void _showEditProfileDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser!;
    final nameCtrl = TextEditingController(text: user.name);
    final phoneCtrl = TextEditingController(text: user.phone);
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.dividerStrongC(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: AppTheme.primaryColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.dividerC(context),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.badge_rounded),
                          ),
                          textCapitalization: TextCapitalization.words,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Name is required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: phoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            prefixIcon: Icon(Icons.phone_rounded),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          initialValue: user.email,
                          decoration: const InputDecoration(
                            labelText: 'Email (cannot be changed)',
                            prefixIcon: Icon(Icons.email_rounded),
                          ),
                          readOnly: true,
                          style: TextStyle(color: AppTheme.textTer(context)),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(sheetCtx),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: BorderSide(
                                    color: AppTheme.dividerStrongC(context),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: AppTheme.textSec(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Consumer<AuthProvider>(
                                builder: (context, auth, _) => ElevatedButton(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () async {
                                          if (!formKey.currentState!
                                              .validate()) {
                                            return;
                                          }
                                          final ok = await auth.updateProfile(
                                            name: nameCtrl.text.trim(),
                                            phone: phoneCtrl.text.trim(),
                                          );
                                          if (sheetCtx.mounted) {
                                            Navigator.pop(sheetCtx);
                                            HapticFeedback.mediumImpact();
                                            if (ok) {
                                              showSuccessSnackBar(
                                                context,
                                                'Profile updated!',
                                              );
                                            } else {
                                              showErrorSnackBar(
                                                context,
                                                auth.errorMessage ??
                                                    'Failed to update',
                                              );
                                            }
                                            auth.clearError();
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: auth.isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'Save',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser!;
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.dividerStrongC(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.dangerColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.delete_forever_rounded,
                          color: AppTheme.dangerColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        'Delete Account',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.dangerColor,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.dividerC(context),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerColor.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.dangerColor.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: AppTheme.dangerColor,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'This action is permanent',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.dangerColor,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                user.isAdmin
                                    ? 'Your account and ALL company data (products, transactions, categories, staff accounts) will be permanently deleted.'
                                    : 'Your account will be permanently removed. You will lose access to all company data.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textPri(context),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'Enter your password to confirm:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: passwordCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_rounded),
                          ),
                          obscureText: true,
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Password is required'
                              : null,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(sheetCtx),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: BorderSide(
                                    color: AppTheme.dividerStrongC(context),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: AppTheme.textSec(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Consumer<AuthProvider>(
                                builder: (context, auth, _) => ElevatedButton(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () async {
                                          if (!formKey.currentState!
                                              .validate()) {
                                            return;
                                          }
                                          final ok = await auth.deleteAccount(
                                            passwordCtrl.text,
                                          );
                                          if (sheetCtx.mounted) {
                                            Navigator.pop(sheetCtx);
                                          }
                                          if (ok && context.mounted) {
                                            Navigator.of(context).popUntil(
                                              (route) => route.isFirst,
                                            );
                                          } else if (context.mounted) {
                                            showErrorSnackBar(
                                              context,
                                              auth.errorMessage ??
                                                  'Failed to delete account',
                                            );
                                            auth.clearError();
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.dangerColor,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: auth.isLoading
                                      ? SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppTheme.surface(context),
                                          ),
                                        )
                                      : const Text(
                                          'Delete Account',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPw = TextEditingController();
    final newPw = TextEditingController();
    final confirmPw = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      constraints: Responsive.sheetConstraints(context),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.dividerStrongC(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.indigoColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.lock_reset_rounded,
                          color: AppTheme.indigoColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Change Password',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.dividerC(context),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Form(
                    key: formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: currentPw,
                          decoration: const InputDecoration(
                            labelText: 'Current Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: newPw,
                          decoration: const InputDecoration(
                            labelText: 'New Password',
                            prefixIcon: Icon(Icons.lock),
                          ),
                          obscureText: true,
                          onChanged: (_) => formKey.currentState?.validate(),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (v.length < 6) return 'Min 6 characters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: confirmPw,
                          decoration: const InputDecoration(
                            labelText: 'Confirm New Password',
                            prefixIcon: Icon(Icons.lock),
                          ),
                          obscureText: true,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (v != newPw.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(sheetCtx),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: BorderSide(
                                    color: AppTheme.dividerStrongC(context),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: AppTheme.textSec(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Consumer<AuthProvider>(
                                builder: (context, auth, _) => ElevatedButton(
                                  onPressed: auth.isLoading
                                      ? null
                                      : () async {
                                          if (!formKey.currentState!
                                              .validate()) {
                                            return;
                                          }
                                          final ok = await auth.changePassword(
                                            currentPw.text,
                                            newPw.text,
                                          );
                                          if (sheetCtx.mounted) {
                                            Navigator.pop(sheetCtx);
                                            HapticFeedback.mediumImpact();
                                            if (ok) {
                                              showSuccessSnackBar(
                                                context,
                                                'Password changed!',
                                              );
                                            } else {
                                              showErrorSnackBar(
                                                context,
                                                auth.errorMessage ?? 'Failed',
                                              );
                                            }
                                            auth.clearError();
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: auth.isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'Change',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

class _SettingsSectionBlock extends StatefulWidget {
  final String title;
  final Color accentColor;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _SettingsSectionBlock({
    required this.title,
    required this.accentColor,
    required this.children,
    this.initiallyExpanded = true,
  });

  @override
  State<_SettingsSectionBlock> createState() => _SettingsSectionBlockState();
}

class _SettingsSectionBlockState extends State<_SettingsSectionBlock> {
  late bool _expanded = widget.initiallyExpanded;

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
        Semantics(
          button: true,
          expanded: _expanded,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _toggle,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SectionHeader(
                      title: widget.title,
                      color: widget.accentColor,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.0 : -0.25,
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6, top: 2, bottom: 6),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.iconMute(context),
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: _SettingsCard(children: widget.children),
          secondChild: const SizedBox(width: double.infinity, height: 0),
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: reduce
              ? Duration.zero
              : const Duration(milliseconds: 220),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    final webLux = kIsWeb && Responsive.isDesktop(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 4,
        bottom: webLux ? 10 : 8,
        top: webLux ? 6 : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: webLux ? 4 : 3,
                height: webLux ? 16 : 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: webLux ? 10 : 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: webLux ? 12.5 : 11,
                  fontWeight: FontWeight.w800,
                  color: webLux
                      ? AppTheme.textSec(context)
                      : AppTheme.iconMute(context),
                  letterSpacing: webLux ? 1.4 : 1.2,
                ),
              ),
            ],
          ),
          if (webLux) ...[
            const SizedBox(height: 8),
            Container(
              height: 1,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.45),
                    color.withValues(alpha: 0.06),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final webLux = kIsWeb && Responsive.isDesktop(context);
    return Padding(
      padding: EdgeInsets.only(bottom: webLux ? 2 : 0),
      child: GlassPanel(
        borderRadius: webLux ? 18 : 16,
        useContentVariant: true,
        child: Column(children: children),
      ),
    );
  }
}

class _SettingsTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final webLux = kIsWeb && Responsive.isDesktop(context);
    if (!webLux) {
      return Material(
        color: Colors.transparent,
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -2),
          leading: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: widget.iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, color: widget.iconColor, size: 18),
          ),
          title: Text(
            widget.title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          subtitle: widget.subtitle != null
              ? Text(
                  widget.subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTer(context),
                  ),
                )
              : null,
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            color: AppTheme.iconMute(context),
            size: 13,
          ),
          onTap: widget.onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 0,
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _hover
              ? AppTheme.primaryColor.withValues(alpha: 0.055)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hover ? AppTheme.dividerC(context) : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.icon, color: widget.iconColor, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle!,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textTer(context),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.iconMute(context),
                    size: 24,
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

class _ManageListItem extends StatelessWidget {
  final String name;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  const _ManageListItem({
    required this.name,
    this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerC(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPri(context),
              ),
            ),
          ),
          if (onEdit != null)
            Material(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.edit_outlined,
                    color: AppTheme.primaryColor,
                    size: 16,
                  ),
                ),
              ),
            ),
          if (onEdit != null) const SizedBox(width: 8),
          Material(
            color: AppTheme.dangerColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.close_rounded,
                  color: AppTheme.dangerColor,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
