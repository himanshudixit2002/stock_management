import 'package:flutter/material.dart';
import '../../config/theme.dart';

Widget legalHeader(String subtitle) {
  return Text(
    subtitle,
    style: TextStyle(
      fontSize: 14,
      color: AppTheme.primaryColor.withValues(alpha: 0.85),
      fontWeight: FontWeight.w500,
    ),
  );
}

Widget legalMeta(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: AppTheme.textSec(context)),
    ),
  );
}

Widget legalSection(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppTheme.primaryColor,
      ),
    ),
  );
}

Widget legalSubSection(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPri(context),
      ),
    ),
  );
}

Widget legalBody(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 14,
        color: AppTheme.textSec(context),
        height: 1.6,
      ),
    ),
  );
}

Widget legalBulletList(BuildContext context, List<String> items) {
  return Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '\u2022  ',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSec(context),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
}

Widget legalFooter(BuildContext context) {
  return Center(
    child: Text(
      '\u00A9 2026 SmartShelfKart. All rights reserved.',
      style: TextStyle(
        fontSize: 12,
        color: AppTheme.textSec(context).withValues(alpha: 0.6),
      ),
    ),
  );
}
