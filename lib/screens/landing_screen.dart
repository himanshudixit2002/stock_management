import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme.dart';
import '../widgets/animated_list_item.dart';
import '../utils/responsive.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: Responsive.contentMaxWidth(context)),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Hero section with gradient
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFE0F2F1), Color(0xFFF7F8FA)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(Responsive.horizontalPadding(context) + 8, 56, Responsive.horizontalPadding(context) + 8, 40),
                      child: Column(
                        children: [
                          Hero(
                            tag: 'app-logo',
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: AppTheme.softShadow,
                              ),
                              child: Image.asset('logo.png', width: 72, height: 72),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Smart Shelf Kart',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryDark,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Simple, powerful inventory management\nfor your business',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[600],
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // Gradient CTA button
                          SizedBox(
                            width: double.infinity,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: AppTheme.coloredShadow(AppTheme.primaryColor),
                              ),
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.pushNamed(context, '/register'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Get Started Free',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward_rounded, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/login'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: const Text(
                                'Login to Your Account',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.verified_user_rounded,
                                  size: 16, color: Colors.grey[400]),
                              const SizedBox(width: 6),
                              Text(
                                'Trusted by growing businesses',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Features section
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: Responsive.horizontalPadding(context),
                      vertical: 32,
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 32,
                              height: 3,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Everything you need',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              width: 32,
                              height: 3,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (Responsive.isWide(context))
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: _features.asMap().entries.map((entry) {
                              final i = entry.key;
                              final f = entry.value;
                              return SizedBox(
                                width: (MediaQuery.sizeOf(context).width.clamp(0, Responsive.contentMaxWidth(context)) - Responsive.horizontalPadding(context) * 2 - 12) / 2,
                                child: AnimatedListItem(
                                  index: i,
                                  child: _FeatureCard(
                                    icon: f.$1,
                                    title: f.$2,
                                    description: f.$3,
                                    color: f.$4,
                                  ),
                                ),
                              );
                            }).toList(),
                          )
                        else
                          ..._features.asMap().entries.map((entry) {
                            final i = entry.key;
                            final f = entry.value;
                            return AnimatedListItem(
                              index: i,
                              child: _FeatureCard(
                                icon: f.$1,
                                title: f.$2,
                                description: f.$3,
                                color: f.$4,
                              ),
                            );
                          }),
                      ],
                    ),
                  ),

                  // Footer
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: Responsive.horizontalPadding(context), vertical: 20),
                    color: const Color(0xFFF0F4F8),
                    child: Column(
                      children: [
                        Text(
                          '\u00A9 2026 Smart Shelf Kart',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _FooterChip(
                              label: 'Privacy',
                              onTap: () => _openUrl(context, 'https://smartshelfkart.com/privacy-policy.html'),
                            ),
                            _FooterChip(
                              label: 'Terms',
                              onTap: () => _openUrl(context, 'https://smartshelfkart.com/terms.html'),
                            ),
                            _FooterChip(
                              label: 'Support',
                              onTap: () => _openUrl(context, 'https://smartshelfkart.com/support.html'),
                            ),
                            _FooterChip(
                              label: 'Data Deletion',
                              onTap: () => _openUrl(context, 'https://smartshelfkart.com/data-deletion.html'),
                            ),
                          ],
                        ),
                      ],
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

  static final _features = <(IconData, String, String, Color)>[
    (Icons.location_on_rounded, 'Multi-Location Tracking',
        'Track stock across warehouses, shops, and any custom locations.',
        AppTheme.primaryColor),
    (Icons.swap_horiz_rounded, 'Stock Transfers',
        'Move inventory between locations with full audit trail.',
        AppTheme.indigoColor),
    (Icons.analytics_rounded, 'Reports & Analytics',
        'Detailed charts, trends, and exportable reports.',
        AppTheme.infoColor),
    (Icons.upload_file_rounded, 'Import & Export',
        'Bulk import from Excel/CSV and export your data anytime.',
        AppTheme.successColor),
    (Icons.people_rounded, 'Team Management',
        'Add staff members with role-based access control.',
        AppTheme.warningColor),
    (Icons.broken_image_rounded, 'Damage Tracking',
        'Record and monitor damaged goods with reasons.',
        AppTheme.dangerColor),
  ];

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not open the link. Please try again later.'),
              backgroundColor: AppTheme.dangerColor,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'RETRY',
                textColor: Colors.white,
                onPressed: () => _openUrl(context, url),
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong opening the link.'),
            backgroundColor: AppTheme.dangerColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
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
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
