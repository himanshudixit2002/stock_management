import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import '../../utils/url_helper.dart';
import '../../widgets/animations.dart';
import '../../widgets/glass_panel.dart';
import 'legal_widgets.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.horizontalPadding(context),
              vertical: 20,
            ),
            physics: Responsive.scrollPhysics(context),
            children: [
              FadeSlideIn(
                child: legalHero(
                  context,
                  icon: Icons.support_agent_rounded,
                  title: 'Support',
                  subtitle: 'SmartShelfKart App',
                ),
              ),
              const SizedBox(height: 16),
              FadeSlideIn(index: 1, child: _buildContactSection(context)),
              const SizedBox(height: 16),
              FadeSlideIn(index: 2, child: _buildFaqSection(context)),
              const SizedBox(height: 24),
              FadeSlideIn(index: 3, child: legalFooter(context)),
              const SizedBox(height: 12),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildContactSection(BuildContext context) {
    return GlassSectionCard(
      title: 'Contact Us',
      icon: Icons.headset_mic_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          PlayfulPressable(
            borderRadius: BorderRadius.circular(12),
            onTap: () => openUrl(context, 'mailto:support@smartshelfkart.com'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                ),
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
                  const Text(
                    'support@smartshelfkart.com',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'We typically respond within 24-48 hours',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSec(context).withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaqSection(BuildContext context) {
    return GlassSectionCard(
      title: 'Frequently Asked Questions',
      icon: Icons.help_outline_rounded,
      child: Column(
        children: _faqItems
            .map((faq) => _SupportFaqTile(question: faq.$1, answer: faq.$2))
            .toList(),
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

class _SupportFaqTile extends StatelessWidget {
  final String question;
  final String answer;

  const _SupportFaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.question_mark_rounded,
            size: 18,
            color: AppTheme.primaryColor,
          ),
        ),
        title: Text(
          question,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPri(context),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Text(
              answer,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppTheme.textSec(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
