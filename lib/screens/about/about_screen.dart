import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../utils/responsive.dart';
import '../../widgets/glass_panel.dart';
import '../../config/app_navigation.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _packageInfo = info);
  }

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(hPad, 24, hPad, 40),
              children: [
                _buildLogoSection(context),
                const SizedBox(height: 28),
                _buildAppInfoSection(context),
                const SizedBox(height: 16),
                _buildLinksSection(context),
                const SizedBox(height: 16),
                _buildRateSection(context),
                const SizedBox(height: 32),
                _buildFlutterBadge(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            gradient: AppTheme.heroGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppTheme.coloredShadow(AppTheme.primaryColor),
          ),
          child: const Center(
            child: Icon(
              Icons.inventory_2_rounded,
              size: 44,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'SmartShelfKart',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPri(context),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Simple Inventory Management',
          style: TextStyle(fontSize: 14, color: AppTheme.textSec(context)),
        ),
      ],
    );
  }

  Widget _buildAppInfoSection(BuildContext context) {
    final version = _packageInfo?.version ?? '...';
    final buildNumber = _packageInfo?.buildNumber ?? '...';

    return GlassSectionCard(
      title: 'App Info',
      icon: Icons.info_outline_rounded,
      child: Column(
        children: [
          _InfoTile(icon: Icons.tag_rounded, label: 'Version', value: version),
          Divider(height: 1, color: AppTheme.dividerC(context)),
          _InfoTile(
            icon: Icons.build_rounded,
            label: 'Build',
            value: buildNumber,
          ),
          Divider(height: 1, color: AppTheme.dividerC(context)),
          _InfoTile(
            icon: Icons.business_rounded,
            label: 'Package',
            value: _packageInfo?.packageName ?? '...',
          ),
        ],
      ),
    );
  }

  Widget _buildLinksSection(BuildContext context) {
    return GlassSectionCard(
      title: 'Links',
      icon: Icons.link_rounded,
      iconColor: AppTheme.infoColor,
      child: Column(
        children: [
          _LinkTile(
            icon: Icons.article_rounded,
            iconColor: AppTheme.primaryColor,
            title: 'Open-Source Licenses',
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'SmartShelfKart',
                applicationVersion: _packageInfo?.version,
                applicationIcon: Container(
                  width: 56,
                  height: 56,
                  margin: const EdgeInsets.only(top: 8),
                  decoration: BoxDecoration(
                    gradient: AppTheme.heroGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.inventory_2_rounded,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),
          Divider(height: 1, color: AppTheme.dividerC(context)),
          _LinkTile(
            icon: Icons.support_agent_rounded,
            iconColor: AppTheme.accentColor,
            title: 'Support & Feedback',
            onTap: () => context.pushAppRoute(AppRoutes.support),
          ),
        ],
      ),
    );
  }

  Widget _buildRateSection(BuildContext context) {
    return GlassSectionCard(
      title: 'Rate Us',
      icon: Icons.star_rounded,
      iconColor: AppTheme.warningColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enjoying SmartShelfKart?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPri(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Leave us a rating on the app store to help other businesses discover us.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSec(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(
              5,
              (i) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.star_rounded,
                  size: 28,
                  color: AppTheme.warningColor.withValues(
                    alpha: 0.3 + (i < 3 ? 0.7 : 0),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlutterBadge(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.isDark(context)
              ? Colors.white.withValues(alpha: 0.06)
              : AppTheme.primaryColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.isDark(context)
                ? Colors.white.withValues(alpha: 0.1)
                : AppTheme.primaryColor.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FlutterLogo(size: 18),
            const SizedBox(width: 8),
            Text(
              'Made with Flutter',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSec(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.iconMute(context)),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: AppTheme.textSec(context)),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPri(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  const _LinkTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textPri(context),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: AppTheme.iconMute(context),
        ),
        onTap: onTap,
      ),
    );
  }
}
