import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../utils/url_helper.dart';
import '../config/routes.dart';
import '../config/theme.dart';
import '../widgets/animated_list_item.dart';
import '../utils/responsive.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = Responsive.isWide(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Responsive.contentMaxWidth(context),
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildHeroSection(context, isWide),
                  _buildFeaturesSection(context, screenWidth, isWide),
                  _buildFooter(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, bool isWide) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D3B34), Color(0xFF00695C), Color(0xFF00897B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Responsive.horizontalPadding(context) + 8,
          isWide ? 72 : 56,
          Responsive.horizontalPadding(context) + 8,
          isWide ? 64 : 48,
        ),
        child: Column(
          children: [
            Hero(
              tag: 'app-logo',
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Image.asset('logo.png', width: 56, height: 56),
              ),
            ),
            const SizedBox(height: 28),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.white, Color(0xFF80CBC4)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ).createShader(bounds),
              child: const Text(
                'Smart Inventory',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.surfaceColor,
                  letterSpacing: -1,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Modern inventory management\nthat scales with your business',
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.78),
                height: 1.6,
                letterSpacing: 0.1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8A65), Color(0xFFFF6E40)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF8A65).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, AppRoutes.register),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.surfaceColor,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: AppTheme.surfaceColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.login),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.surfaceColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Login to Your Account',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TrustBadge(icon: Icons.shield_rounded, label: 'Secure'),
                Container(
                  width: 1,
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                _TrustBadge(icon: Icons.speed_rounded, label: 'Real-time'),
                Container(
                  width: 1,
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                _TrustBadge(
                  icon: Icons.devices_rounded,
                  label: 'Multi-platform',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesSection(
    BuildContext context,
    double screenWidth,
    bool isWide,
  ) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppTheme.scaffoldGradient),
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 40,
      ),
      child: Column(
        children: [
          Text(
            'EVERYTHING YOU NEED',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppTheme.primaryColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Powerful features, simple interface',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = isWide
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: _features.asMap().entries.map((entry) {
                  return SizedBox(
                    width: cardWidth,
                    child: AnimatedListItem(
                      index: entry.key,
                      child: _GlassFeatureCard(
                        icon: entry.value.$1,
                        title: entry.value.$2,
                        description: entry.value.$3,
                        color: entry.value.$4,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 24,
      ),
      decoration: const BoxDecoration(color: Color(0xFF1A1D23)),
      child: Column(
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _FooterLink(
                label: 'Privacy',
                onTap: () => _openUrl(
                  context,
                  'https://smartinventory.com/privacy-policy.html',
                ),
              ),
              _FooterLink(
                label: 'Terms',
                onTap: () =>
                    _openUrl(context, 'https://smartinventory.com/terms.html'),
              ),
              _FooterLink(
                label: 'Support',
                onTap: () => _openUrl(
                  context,
                  'https://smartinventory.com/support.html',
                ),
              ),
              _FooterLink(
                label: 'Data Deletion',
                onTap: () => _openUrl(
                  context,
                  'https://smartinventory.com/data-deletion.html',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '\u00A9 2026 Smart Inventory. All rights reserved.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  static final _features = <(IconData, String, String, Color)>[
    (
      Icons.location_on_rounded,
      'Multi-Location',
      'Track stock across warehouses, shops, and more.',
      AppTheme.primaryColor,
    ),
    (
      Icons.swap_horiz_rounded,
      'Stock Transfers',
      'Move inventory with a full audit trail.',
      AppTheme.indigoColor,
    ),
    (
      Icons.analytics_rounded,
      'Reports & Analytics',
      'Charts, trends, and exportable reports.',
      AppTheme.infoColor,
    ),
    (
      Icons.upload_file_rounded,
      'Import & Export',
      'Bulk import from Excel/CSV anytime.',
      AppTheme.successColor,
    ),
    (
      Icons.people_rounded,
      'Team Management',
      'Role-based access for your staff.',
      AppTheme.warningColor,
    ),
    (
      Icons.broken_image_rounded,
      'Damage Tracking',
      'Record and monitor damaged goods.',
      AppTheme.dangerColor,
    ),
  ];

  Future<void> _openUrl(BuildContext context, String url) =>
      openUrl(context, url);
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _GlassFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _GlassFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final container = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kIsWeb ? AppTheme.glassSurfaceContent : AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorderContent),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textTertiary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: container,
        ),
      );
    }
    return container;
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.55),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
