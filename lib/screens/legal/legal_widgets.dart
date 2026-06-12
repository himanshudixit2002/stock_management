import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../widgets/glass_panel.dart';

/// A glass hero card for legal/info documents: gradient icon badge, document
/// title, a short subtitle and any number of metadata lines (dates, etc.).
Widget legalHero(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  List<String> meta = const [],
}) {
  return GlassPanel(
    useContentVariant: true,
    padding: const EdgeInsets.all(20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(child: Icon(icon, color: Colors.white, size: 26)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPri(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.primaryColor.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
              ...meta.map(
                (text) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget legalSection(String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 4,
          height: 18,
          margin: const EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor,
            ),
          ),
        ),
      ],
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
