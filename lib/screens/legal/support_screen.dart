import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import '../../utils/url_helper.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support'),
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
              Text(
                'SmartShelfKart App',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.primaryColor.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              _card(
                context,
                children: [
                  const Text(
                    'Contact Us',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We\'re here to help! If you have any questions, issues, or '
                    'feedback about SmartShelfKart, please reach out to us.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSec(context),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Email us at',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSec(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => openUrl(
                            context,
                            'mailto:support@smartshelfkart.com',
                          ),
                          child: const Text(
                            'support@smartshelfkart.com',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'We typically respond within 24-48 hours',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSec(
                              context,
                            ).withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _card(
                context,
                children: [
                  const Text(
                    'Frequently Asked Questions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._faqItems.map((faq) => _faqTile(context, faq.$1, faq.$2)),
                ],
              ),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  '\u00A9 2026 SmartShelfKart. All rights reserved.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSec(context).withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  static final _faqItems = <(String, String)>[
    (
      'How do I add a new product?',
      'From the home screen, tap "Stock In" and fill in the product details. '
          'If the product doesn\'t exist yet, go to Products and tap the "+" '
          'button to create it first.',
    ),
    (
      'Can I track products across multiple locations?',
      'Yes! SmartShelfKart supports multi-location tracking. When adding or '
          'removing stock, specify the location. Each product shows its quantity '
          'breakdown by location.',
    ),
    (
      'How do I transfer stock between locations?',
      'Use the "Transfer" feature from the home screen. Select the product, '
          'choose the source and destination locations, and enter the quantity '
          'to transfer.',
    ),
    (
      'Can I export my data?',
      'Yes! Go to the Export section from the home screen. You can export '
          'products, transactions, categories, or a full report in CSV or '
          'Excel format.',
    ),
    (
      'How do I import data from Excel/CSV?',
      'Go to the Import section, download the template file, fill it with '
          'your data, and upload it back. The app will parse and import your '
          'products automatically.',
    ),
    (
      'How do I delete my account?',
      'You can delete your account from Settings > Delete Account, or by '
          'emailing us at support@smartshelfkart.com.',
    ),
    (
      'Is my data secure?',
      'Yes. We use Google Firebase for secure data storage and authentication. '
          'All data is encrypted in transit and at rest.',
    ),
  ];
}

Widget _faqTile(BuildContext context, String question, String answer) {
  return Container(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: AppTheme.dividerC(context), width: 1),
      ),
    ),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPri(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          answer,
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textSec(context),
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}
