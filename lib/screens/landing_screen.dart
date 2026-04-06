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
    final isWide = Responsive.isWide(context);

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
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
                  _buildCapabilitiesStrip(context),
                  _buildFeatureCategories(context, isWide),
                  _buildHighlightsGrid(context, isWide),
                  _buildCtaSection(context),
                  _buildFooter(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------- HERO ---------------
  Widget _buildHeroSection(BuildContext context, bool isWide) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppTheme.isDark(context)
            ? const LinearGradient(
                colors: [Color(0xFF1A2C2B), Color(0xFF161616), Color(0xFF121212)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : const LinearGradient(
                colors: [Color(0xFFE0F2F1), Color(0xFFF7F8FA), Color(0xFFFFFFFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Responsive.horizontalPadding(context) + 8,
          isWide ? 40 : 28,
          Responsive.horizontalPadding(context) + 8,
          isWide ? 32 : 20,
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface(context),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                ),
              ),
              child: Image.asset('logo.png', width: 44, height: 44),
            ),
            const SizedBox(height: 20),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF00695C), Color(0xFF00897B), Color(0xFF26A69A)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ).createShader(bounds),
              child: const Text(
                'SmartShelfKart',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.2,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'All-in-one inventory management\nfor modern businesses',
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.textSec(context),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Center(
              child: SizedBox(
                width: isWide ? 320 : double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppTheme.coloredShadow(AppTheme.primaryColor),
                  ),
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.register),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Get Started Free',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.surface(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded,
                            size: 20, color: AppTheme.surface(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                width: isWide ? 320 : double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.login),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    side: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
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
            ),
          ],
        ),
      ),
    );
  }

  // --------------- CAPABILITIES STRIP ---------------
  Widget _buildCapabilitiesStrip(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(
          top: BorderSide(color: AppTheme.dividerC(context)),
          bottom: BorderSide(color: AppTheme.dividerC(context)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CapBadge(Icons.shield_rounded, 'Secure'),
          _capDot(context),
          _CapBadge(Icons.speed_rounded, 'Real-time'),
          _capDot(context),
          _CapBadge(Icons.devices_rounded, 'Multi-platform'),
          _capDot(context),
          _CapBadge(Icons.business_rounded, 'Multi-company'),
        ],
      ),
    );
  }

  Widget _capDot(BuildContext context) => Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: AppTheme.dividerStrongC(context),
          shape: BoxShape.circle,
        ),
      );

  // --------------- FEATURE CATEGORIES ---------------
  Widget _buildFeatureCategories(BuildContext context, bool isWide) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 24,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'EVERYTHING YOU NEED',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'One app. Every inventory task.',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPri(context),
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ..._featureGroups.asMap().entries.map((entry) {
            final group = entry.value;
            return AnimatedListItem(
              index: entry.key,
              child: _FeatureGroupCard(
                icon: group.icon,
                title: group.title,
                color: group.color,
                items: group.items,
              ),
            );
          }),
        ],
      ),
    );
  }

  // --------------- HIGHLIGHTS GRID ---------------
  Widget _buildHighlightsGrid(BuildContext context, bool isWide) {
    const highlights = <(IconData, String, String)>[
      (Icons.qr_code_scanner_rounded, 'Barcode Scanner', 'Scan & look up instantly'),
      (Icons.business_rounded, 'Multi-Company', 'Manage multiple businesses'),
      (Icons.upload_file_rounded, 'Excel Import/Export', 'Bulk data anytime'),
      (Icons.notifications_active_rounded, 'Smart Alerts', 'Low stock & expiry'),
      (Icons.favorite_rounded, 'Favorites', 'Quick access to key products'),
      (Icons.history_rounded, 'Audit Log', 'Full traceability'),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(
          top: BorderSide(color: AppTheme.dividerC(context)),
          bottom: BorderSide(color: AppTheme.dividerC(context)),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Plus',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSec(context),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = isWide ? 3 : 2;
              final spacing = 10.0;
              final cardW =
                  (constraints.maxWidth - spacing * (cols - 1)) / cols;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: highlights.asMap().entries.map((e) {
                  final h = e.value;
                  return AnimatedListItem(
                    index: e.key,
                    child: SizedBox(
                      width: cardW,
                      child: _HighlightChip(
                          icon: h.$1, title: h.$2, subtitle: h.$3),
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

  // --------------- CTA ---------------
  Widget _buildCtaSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context) + 8,
        vertical: 32,
      ),
      decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_rounded, size: 36, color: Colors.white),
          const SizedBox(height: 12),
          const Text(
            'Ready to take control\nof your inventory?',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.3,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Free forever. No credit card required.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: Responsive.isWide(context) ? 320 : double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, AppRoutes.register),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surface(context),
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Create Free Account',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------- FOOTER ---------------
  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: Responsive.horizontalPadding(context),
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(top: BorderSide(color: AppTheme.dividerC(context))),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _FooterLink(
                label: 'Privacy Policy',
                onTap: () {
                  if (kIsWeb) {
                    _openUrl(context,
                        'https://smartshelfkart.com/privacy-policy.html');
                  } else {
                    Navigator.pushNamed(context, AppRoutes.privacyPolicy);
                  }
                },
              ),
              _FooterLink(
                label: 'Terms',
                onTap: () {
                  if (kIsWeb) {
                    _openUrl(context, 'https://smartshelfkart.com/terms.html');
                  } else {
                    Navigator.pushNamed(context, AppRoutes.terms);
                  }
                },
              ),
              _FooterLink(
                label: 'Support',
                onTap: () {
                  if (kIsWeb) {
                    _openUrl(
                        context, 'https://smartshelfkart.com/support.html');
                  } else {
                    Navigator.pushNamed(context, AppRoutes.support);
                  }
                },
              ),
              _FooterLink(
                label: 'Data Deletion',
                onTap: () {
                  if (kIsWeb) {
                    _openUrl(context,
                        'https://smartshelfkart.com/data-deletion.html');
                  } else {
                    Navigator.pushNamed(context, AppRoutes.dataDeletion);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '\u00A9 2026 SmartShelfKart. All rights reserved.',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSec(context).withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) =>
      openUrl(context, url);
}

// ======================================================================
// DATA
// ======================================================================

class _FeatureGroup {
  final IconData icon;
  final String title;
  final Color color;
  final List<String> items;
  const _FeatureGroup(this.icon, this.title, this.color, this.items);
}

final _featureGroups = <_FeatureGroup>[
  _FeatureGroup(
    Icons.inventory_2_rounded,
    'Stock Operations',
    AppTheme.primaryColor,
    [
      'Stock In / Out / Transfer',
      'Stock Adjustment & Counting',
      'Multi-location tracking',
      'Warehouse zone management',
    ],
  ),
  _FeatureGroup(
    Icons.shopping_cart_rounded,
    'Orders & Returns',
    AppTheme.indigoColor,
    [
      'Purchase orders',
      'Sales orders',
      'Returns management',
      'Customer & vendor database',
    ],
  ),
  _FeatureGroup(
    Icons.analytics_rounded,
    'Analytics & Reports',
    AppTheme.infoColor,
    [
      'Dashboard with live charts',
      'Profit & loss, ABC analysis',
      'Valuation trends & price history',
      'Damage history & stock forecast',
    ],
  ),
  _FeatureGroup(
    Icons.people_rounded,
    'Team & Security',
    AppTheme.warningColor,
    [
      'Role-based access (admin / staff)',
      'Granular permissions per user',
      'Multi-company support',
      'Full audit trail',
    ],
  ),
  _FeatureGroup(
    Icons.bolt_rounded,
    'Productivity',
    AppTheme.successColor,
    [
      'Barcode scanner (camera + manual)',
      'Excel import / export / update',
      'Bulk stock-in & bulk edit',
      'Batch tracking & expiry alerts',
    ],
  ),
];

// ======================================================================
// WIDGETS
// ======================================================================

class _CapBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CapBadge(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.primaryColor),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSec(context),
          ),
        ),
      ],
    );
  }
}

class _FeatureGroupCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<String> items;

  const _FeatureGroupCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.14),
                      color.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPri(context),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: color.withValues(alpha: 0.10)),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _HighlightChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _HighlightChip({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerC(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryColor),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPri(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSec(context),
            ),
          ),
        ],
      ),
    );
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
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.primaryColor.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
