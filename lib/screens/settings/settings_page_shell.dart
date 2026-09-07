import 'package:flutter/material.dart';

import '../../config/settings_catalog.dart';
import '../../config/theme.dart';
import '../../utils/responsive.dart';
import '../../widgets/animations.dart';

/// The body of a settings sub-page.
///
/// Every sub-page is the same shape — a scrolling column of named groups, each
/// a header over a short run of rows — so the shape lives here rather than
/// being retyped six times. It also fixes the padding at one value, which is
/// what the old screen's per-tile `kIsWeb && isDesktop` forks kept getting
/// slightly differently.
class SettingsPageBody extends StatelessWidget {
  const SettingsPageBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final horizontal = Responsive.horizontalPadding(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(horizontal, AppTheme.spacingMD, horizontal, 40),
      children: children,
    );
  }
}

/// A named run of rows on a settings page.
///
/// [anchor] is what a settings search hit scrolls to: the group, not the
/// individual field, which is why the breadcrumb on a search result names a
/// group too.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: AppTheme.spacingSM),
          ...children,
        ],
      ),
    );
  }
}

/// A short explanatory note under a group — used where a switch has a
/// consequence worth stating before it is flipped.
class SettingsNote extends StatelessWidget {
  const SettingsNote({super.key, required this.text, this.icon, this.color});

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.info(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingMD),
        decoration: BoxDecoration(
          color: AppTheme.tint(context, accent),
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon ?? Icons.info_outline_rounded, size: 17, color: accent),
            const SizedBox(width: AppTheme.spacingSM),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSec(context),
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whether [ctx] can see [id], for a sub-page deciding whether to draw a row.
///
/// Sub-pages ask the catalog rather than repeating a permission check, so a row
/// is visible on its page exactly when it is findable in search.
bool canSee(String id, SettingsVisibilityContext ctx) {
  final leaf = SettingsCatalog.leafById(id);
  return leaf != null && isSettingVisible(leaf, ctx);
}
