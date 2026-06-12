import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../utils/responsive.dart';
import '../../widgets/animations.dart';
import '../../widgets/glass_panel.dart';
import '../../config/app_navigation.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqItems = <_FaqItem>[
    _FaqItem(
      question: 'How do I add a product?',
      answer:
          'Navigate to the Products tab, then tap the + button in the bottom-right '
          'corner. Fill in the product details like name, SKU, category, and initial '
          'stock quantity, then tap Save.',
    ),
    _FaqItem(
      question: 'How do stock operations work?',
      answer:
          'Use Stock In to add inventory when you receive goods. Use Stock Out to '
          'remove inventory when items are sold or dispatched. Each operation is '
          'logged with the user, date, quantity, and optional reason.',
    ),
    _FaqItem(
      question: 'How do I transfer stock?',
      answer:
          'Go to Transfer from the Home tab or Dashboard. Select the product, '
          'source location, destination location, and quantity. The transfer is '
          'recorded and both locations are updated automatically.',
    ),
    _FaqItem(
      question: 'Can I import products from Excel?',
      answer:
          'Yes! Go to Settings > Import/Export and choose "Import from Excel". '
          'Download the template first to ensure your spreadsheet matches the '
          'expected format, then upload your file.',
    ),
    _FaqItem(
      question: 'How do I manage users?',
      answer:
          'Only admins can manage users. Go to Settings > Users to invite new '
          'team members, change roles, or revoke access. You can assign staff '
          'permissions for granular control.',
    ),
    _FaqItem(
      question: 'How do batches work?',
      answer:
          'Batches help track expiry dates and lot numbers for perishable or '
          'regulated products. When adding stock, you can assign a batch number '
          'and expiry date. The app will alert you as batches approach expiry.',
    ),
    _FaqItem(
      question: 'How do invoices and payments work?',
      answer:
          'Open Billing to create sales or purchase invoices, record payments, and '
          'see outstanding amounts. Draft invoices can be edited; sent and paid '
          'states help you track what is still due. Your admin can enable billing '
          'and set prefixes, tax labels, and default terms in billing settings.',
    ),
    _FaqItem(
      question:
          'What is the difference between scanning a barcode and capturing one on a product?',
      answer:
          'From search or stock flows, scanning looks up an existing product by '
          'barcode. When adding or editing a product, the barcode action captures '
          'a code to store on that product (or you can type it). On mobile, '
          'capture uses the camera; on web, use manual entry.',
    ),
    _FaqItem(
      question: 'How does global search work? Can I use filters?',
      answer:
          'Use the search field on Home or the dedicated search screen to find '
          'products and shortcuts. You can combine text with hints such as '
          'stock:low for low stock, stock:out for out of stock, and cat: followed '
          'by a category name to narrow results. Exact behavior may vary by '
          'screen; try the prefix that matches what you see in the search UI.',
    ),
    _FaqItem(
      question: 'Can I customize the Home screen?',
      answer:
          'Yes. Go to Settings and open home customization to show or hide quick '
          'actions and arrange what appears on your dashboard. Changes apply for '
          'your account so you can prioritize the tools you use most.',
    ),
    _FaqItem(
      question: 'Where do roles and permissions apply?',
      answer:
          'Admins manage users and roles under Settings. Each role can grant or '
          'deny actions such as viewing products, importing Excel, creating '
          'invoices, or managing staff. If a menu item is missing, ask an admin '
          'to check your role permissions.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
        child: Center(
          child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
            physics: Responsive.scrollPhysics(context),
            children: [
              FadeSlideIn(child: _buildQuickStartSection(context)),
              const SizedBox(height: 24),
              FadeSlideIn(index: 1, child: _buildFaqSection(context)),
              const SizedBox(height: 24),
              FadeSlideIn(index: 2, child: _buildContactSection(context)),
              const SizedBox(height: 32),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildQuickStartSection(BuildContext context) {
    return GlassSectionCard(
      title: 'Quick Start Guide',
      icon: Icons.rocket_launch_rounded,
      child: Column(
        children: [
          _QuickStartStep(
            step: '1',
            title: 'Add your products',
            subtitle:
                'Create your product catalog with names, SKUs, and categories.',
            icon: Icons.inventory_2_outlined,
          ),
          _QuickStartStep(
            step: '2',
            title: 'Set up locations',
            subtitle: 'Define warehouses or store locations in Settings.',
            icon: Icons.location_on_outlined,
          ),
          _QuickStartStep(
            step: '3',
            title: 'Record stock movements',
            subtitle:
                'Use Stock In, Stock Out, and Transfer to track inventory.',
            icon: Icons.swap_vert_rounded,
          ),
          _QuickStartStep(
            step: '4',
            title: 'Monitor with reports',
            subtitle:
                'View dashboards and reports to stay on top of your stock.',
            icon: Icons.bar_chart_rounded,
            isLast: true,
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
        children: _faqItems.map((item) => _FaqTile(item: item)).toList(),
      ),
    );
  }

  Widget _buildContactSection(BuildContext context) {
    return GlassSectionCard(
      title: 'Need More Help?',
      icon: Icons.support_agent_rounded,
      child: Column(
        children: [
          _ContactOption(
            icon: Icons.headset_mic_outlined,
            title: 'Contact Support',
            subtitle: 'Get help from our support team',
            onTap: () => context.pushAppRoute(AppRoutes.support),
          ),
          const SizedBox(height: 8),
          _ContactOption(
            icon: Icons.feedback_outlined,
            title: 'Send Feedback',
            subtitle: 'Help us improve the app',
            onTap: () => context.pushAppRoute(AppRoutes.support),
          ),
        ],
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});
}

class _FaqTile extends StatelessWidget {
  final _FaqItem item;
  const _FaqTile({required this.item});

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
          item.question,
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
              item.answer,
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

class _QuickStartStep extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isLast;

  const _QuickStartStep({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    step,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 40,
                  margin: const EdgeInsets.only(top: 4),
                  color: AppTheme.dividerC(context),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPri(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSec(context),
                    height: 1.4,
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

class _ContactOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textTer(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textTer(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
