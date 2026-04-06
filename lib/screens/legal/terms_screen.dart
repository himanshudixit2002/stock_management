import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import 'legal_widgets.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
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
              const SizedBox(height: 24),
              legalSection('1. Acceptance of Terms'),
              legalBody(
                context,
                'By downloading, installing, or using SmartShelfKart ("the App"), '
                'you agree to be bound by these Terms of Service. If you do not '
                'agree to these terms, do not use the App.',
              ),
              const SizedBox(height: 20),
              legalSection('2. Description of Service'),
              legalBody(
                context,
                'SmartShelfKart is an inventory management application that allows '
                'users to track products, manage stock levels across multiple '
                'locations, record transactions, and generate reports.',
              ),
              const SizedBox(height: 20),
              legalSection('3. Account Registration'),
              legalBulletList(context, const [
                'You must provide accurate and complete information when creating an account.',
                'You are responsible for maintaining the confidentiality of your account credentials.',
                'You are responsible for all activities that occur under your account.',
                'You must notify us immediately of any unauthorized use of your account.',
              ]),
              const SizedBox(height: 20),
              legalSection('4. Acceptable Use'),
              legalBody(
                context,
                'You agree to use the App only for lawful purposes. You may not:',
              ),
              legalBulletList(context, const [
                'Use the App to store illegal or prohibited content',
                'Attempt to gain unauthorized access to our systems or other users\' data',
                'Interfere with or disrupt the App\'s functionality',
                'Reverse engineer, decompile, or disassemble the App',
                'Use the App for any fraudulent or deceptive purpose',
              ]),
              const SizedBox(height: 20),
              legalSection('5. Your Data'),
              legalBody(
                context,
                'You retain ownership of all inventory data you enter into the App. '
                'We do not claim any ownership rights over your data. You can export '
                'or delete your data at any time.',
              ),
              const SizedBox(height: 20),
              legalSection('6. Service Availability'),
              legalBody(
                context,
                'We strive to maintain high availability but do not guarantee '
                'uninterrupted access. The App may be temporarily unavailable due '
                'to maintenance, updates, or circumstances beyond our control.',
              ),
              const SizedBox(height: 20),
              legalSection('7. Limitation of Liability'),
              legalBody(
                context,
                'The App is provided "as is" without warranties of any kind. We '
                'shall not be liable for any indirect, incidental, special, or '
                'consequential damages arising from your use of the App, including '
                'but not limited to data loss or business interruption.',
              ),
              const SizedBox(height: 20),
              legalSection('8. Modifications'),
              legalBody(
                context,
                'We reserve the right to modify these Terms at any time. Continued '
                'use of the App after changes constitutes acceptance of the '
                'modified Terms.',
              ),
              const SizedBox(height: 20),
              legalSection('9. Termination'),
              legalBody(
                context,
                'We may terminate or suspend your account at any time for violation '
                'of these Terms. You may terminate your account at any time by '
                'requesting account deletion.',
              ),
              const SizedBox(height: 20),
              legalSection('10. Contact'),
              legalBody(
                context,
                'For questions about these Terms, contact us at: support@smartshelfkart.com',
              ),
              const SizedBox(height: 32),
              legalFooter(context),
            ],
          ),
        ),
      ),
    );
  }
}
