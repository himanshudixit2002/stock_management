import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import 'legal_widgets.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: AppTheme.surface(context),
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
              vertical: 20,
            ),
            children: [
              legalHeader('SmartShelfKart App'),
              const SizedBox(height: 8),
              legalMeta(context, 'Effective Date: February 19, 2026'),
              legalMeta(context, 'Last Updated: February 19, 2026'),
              const SizedBox(height: 24),
              legalSection('1. Introduction'),
              legalBody(
                context,
                'Welcome to SmartShelfKart ("we", "our", "us"). We respect your '
                'privacy and are committed to protecting your personal data. This '
                'Privacy Policy explains how we collect, use, and safeguard your '
                'information when you use our mobile and web application.',
              ),
              const SizedBox(height: 20),
              legalSection('2. Information We Collect'),
              legalSubSection(context, 'Account Information'),
              legalBulletList(context, const [
                'Email address - Used for account creation and authentication',
                'Display name - Used to personalize your experience',
                'Password - Securely hashed, never stored in plain text',
              ]),
              legalSubSection(context, 'SmartShelfKart Data'),
              legalBulletList(context, const [
                'Product names, categories, descriptions, and quantities',
                'Stock transaction records (stock in, stock out, damage reports, transfers)',
                'Location data for inventory tracking',
              ]),
              legalSubSection(context, 'Automatically Collected Data'),
              legalBulletList(context, const [
                'Device type and operating system',
                'App usage analytics (via Firebase Analytics)',
                'Crash reports for app improvement',
              ]),
              const SizedBox(height: 20),
              legalSection('3. How We Use Your Information'),
              legalBulletList(context, const [
                'To provide and maintain the SmartShelfKart service',
                'To authenticate your identity and secure your account',
                'To store and manage your inventory data',
                'To improve app performance and user experience',
                'To send important service-related notifications',
              ]),
              const SizedBox(height: 20),
              legalSection('4. Data Storage and Security'),
              legalBody(
                context,
                'Your data is stored securely using Google Firebase services, including:',
              ),
              legalBulletList(context, const [
                'Firebase Authentication - For secure login management',
                'Cloud Firestore - For inventory data storage',
              ]),
              legalBody(
                context,
                'All data is encrypted in transit using TLS/SSL. Firebase provides '
                'enterprise-grade security with SOC 1, SOC 2, and SOC 3 compliance.',
              ),
              const SizedBox(height: 20),
              legalSection('5. Data Sharing'),
              legalBody(
                context,
                'We do not sell, trade, or share your personal data with third '
                'parties. Your inventory data is private and only accessible to you '
                'and authorized users within your account.',
              ),
              legalBody(
                context,
                'We may share anonymized, aggregated data for analytics purposes only.',
              ),
              const SizedBox(height: 20),
              legalSection('6. Your Rights'),
              legalBody(context, 'You have the right to:'),
              legalBulletList(context, const [
                'Access your personal data at any time through the app',
                'Export your data using the built-in export feature',
                'Request deletion of your account and all associated data',
                'Update or correct your personal information',
              ]),
              const SizedBox(height: 20),
              legalSection('7. Data Retention'),
              legalBody(
                context,
                'We retain your data as long as your account is active. If you '
                'delete your account, all associated data will be permanently '
                'removed within 30 days.',
              ),
              const SizedBox(height: 20),
              legalSection('8. Children\'s Privacy'),
              legalBody(
                context,
                'SmartShelfKart is not intended for children under the age of 13. '
                'We do not knowingly collect personal information from children under 13.',
              ),
              const SizedBox(height: 20),
              legalSection('9. Changes to This Policy'),
              legalBody(
                context,
                'We may update this Privacy Policy from time to time. We will '
                'notify you of any changes by posting the new Privacy Policy on '
                'this page and updating the "Last Updated" date.',
              ),
              const SizedBox(height: 20),
              legalSection('10. Contact Us'),
              legalBody(
                context,
                'If you have any questions about this Privacy Policy, please contact us at:',
              ),
              legalBody(context, 'Email: support@smartshelfkart.com'),
              const SizedBox(height: 32),
              legalFooter(context),
            ],
          ),
        ),
      ),
    );
  }
}
