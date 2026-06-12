import 'package:flutter/material.dart';

import '../config/feature_map.dart';
import '../config/theme.dart';
import '../utils/responsive.dart';
import 'animations.dart';

/// A compact contextual header strip for a tab shell: a tinted icon, a title +
/// one-line description of what the tab is for, and an optional row of shortcut
/// chips sourced from [FeatureMap] `tabShortcut` entries.
///
/// Pure UI/navigation: chips push their existing route and never alter
/// providers, permissions, or route names.
class TabContextHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// Already permission-filtered shortcut entries (see
  /// [FeatureMap.visibleEntriesFor]).
  final List<FeatureEntry> shortcuts;

  final EdgeInsetsGeometry? padding;

  const TabContextHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.shortcuts = const [],
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.horizontalPadding(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.primaryColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPri(context),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSec(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (shortcuts.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: Responsive.scrollPhysics(context),
              itemCount: shortcuts.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _ShortcutChip(entry: shortcuts[i]),
            ),
          ),
        ],
      ],
    );

    return FadeSlideIn(
      child: Padding(
        padding:
            padding ?? EdgeInsets.fromLTRB(hPad, 10, hPad, 8),
        child: content,
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  final FeatureEntry entry;

  const _ShortcutChip({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, entry.route),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.dividerC(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.icon, size: 15, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Text(
                entry.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPri(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
