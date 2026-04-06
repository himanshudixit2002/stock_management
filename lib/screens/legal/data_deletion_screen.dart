import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import 'legal_widgets.dart';

class DataDeletionScreen extends StatelessWidget {
  const DataDeletionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Deletion'),
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
              legalHeader('SmartShelfKart'),
              const SizedBox(height: 24),
              legalSection('How to Delete Your Data'),
              legalBody(
                context,
                'We respect your right to control your data. You can request '
                'deletion of your account and all associated data at any time.',
              ),
              const SizedBox(height: 16),
              _stepCard(context, 'Option 1: Delete from within the App', const [
                'Open SmartShelfKart and go to Settings',
                'Under the Account section, tap "Delete Account"',
                'Enter your password to confirm the deletion',
                'Your account and all associated data will be permanently deleted',
              ]),
              const SizedBox(height: 12),
              _stepCard(context, 'Option 2: Request via Email', const [
                'Send an email to support@smartshelfkart.com with the subject line: "Account Deletion Request"',
                'Include the email address associated with your account. We will process your request within 7 business days.',
              ]),
              const SizedBox(height: 20),
              legalSection('What Data Gets Deleted'),
              legalBody(
                context,
                'When you delete your account, the following data is permanently removed:',
              ),
              legalBulletList(context, const [
                'Your account information (email, name, password hash)',
                'All product and inventory records',
                'All stock transaction history (stock in, stock out, damage reports, transfers)',
                'Category data',
                'Location data',
                'Export/import history',
              ]),
              const SizedBox(height: 12),
              _warningBox(
                context,
                'Data deletion is permanent and cannot be undone. We recommend '
                'exporting your data before requesting deletion. You can export '
                'your data to Excel or CSV format using the Export feature in the App.',
              ),
              const SizedBox(height: 20),
              legalSection('Data Deletion Timeline'),
              legalBulletList(context, const [
                'Immediate: Account access is revoked',
                'Within 24 hours: Active data is removed from our systems',
                'Within 30 days: All backup copies are purged',
              ]),
              const SizedBox(height: 20),
              legalSection('Contact Us'),
              legalBody(
                context,
                'If you have questions about data deletion, please contact us at: '
                'support@smartshelfkart.com',
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

Widget _stepCard(BuildContext context, String title, List<String> steps) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.primaryColor.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      border: const Border(
        left: BorderSide(color: AppTheme.primaryColor, width: 4),
      ),
    ),
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
        const SizedBox(height: 8),
        ...steps.asMap().entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Step ${entry.key + 1}: ${entry.value}',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSec(context),
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _warningBox(BuildContext context, String text) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.warningColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: const Border(
        left: BorderSide(color: AppTheme.warningColor, width: 4),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          color: AppTheme.warningColor,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSec(context),
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}
