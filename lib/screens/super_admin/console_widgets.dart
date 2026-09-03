import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/theme.dart';
import '../../models/company_model.dart';
import '../../models/company_plan_model.dart';
import '../../utils/dialogs.dart';
import '../../widgets/document_sheet.dart';
import '../../widgets/animations.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/glass_panel.dart';

/// A small pill label — plan, status, role.
class ConsoleBadge extends StatelessWidget {
  const ConsoleBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Bounded and ellipsised: badges carry user-influenced text (plan labels,
    // roles, statuses) directly inside Rows, where an unbounded pill pushes
    // everything beside it off the edge.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Per-company counts, keyed the way [PlanLimitKeys] expects, so plan caps can
/// be measured against the same numbers the console already displays.
Map<String, int> planUsageOf(CompanyStats stats) => {
  PlanLimitKeys.users: stats.users,
  PlanLimitKeys.products: stats.products,
  PlanLimitKeys.invoices: stats.invoices,
  PlanLimitKeys.salesOrders: stats.salesOrders,
  PlanLimitKeys.purchaseOrders: stats.purchaseOrders,
};

Color statusColorOf(CompanyStatus status) => switch (status) {
  CompanyStatus.active => AppTheme.successColor,
  CompanyStatus.suspended => AppTheme.warningColor,
  CompanyStatus.deleted => AppTheme.dangerColor,
};

/// Renders the loading / error / empty / content states of a console list.
///
/// Every list in the console needs all four, and the one that skipped them —
/// the original global users tab, which showed a spinner whenever the list was
/// empty — is the reason a permission error looked like a hang for weeks.
/// Keeping the triad in one widget means a new list cannot forget it.
class ConsoleListState extends StatelessWidget {
  const ConsoleListState({
    super.key,
    required this.isLoading,
    required this.error,
    required this.isEmpty,
    required this.emptyIcon,
    required this.emptyTitle,
    this.emptySubtitle,
    required this.child,
    this.onRetry,
  });

  final bool isLoading;
  final String? error;
  final bool isEmpty;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptySubtitle;
  final Widget child;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppTheme.dangerColor,
              ),
              const SizedBox(height: 12),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (isEmpty) {
      return EmptyStateWidget(
        icon: emptyIcon,
        title: emptyTitle,
        subtitle: emptySubtitle,
      );
    }
    return child;
  }
}

/// A tappable row that opens the underlying document.
class ConsoleDocTile extends StatelessWidget {
  const ConsoleDocTile({
    super.key,
    required this.data,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    this.iconColor,
    this.sheetTitle,
    this.index = 0,
  });

  final Map<String, dynamic> data;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Color? iconColor;
  final String? sheetTitle;

  /// Position in its list, for the staggered entrance.
  final int index;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppTheme.primaryColor;
    return FadeSlideIn(
      index: index,
      child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        // GlassPanel is an opaque Container with no Material of its own, so an
        // ink splash was painted by the Scaffold *behind* it — every row in the
        // console looked unresponsive to touch. Clip + a transparent Material
        // puts the splash on top, inside the rounded corners.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: icon == null
                  ? null
                  : CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Icon(icon, size: 18, color: color),
                    ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
              // Two-line subtitles need the taller layout, or the avatar and
              // the badge sit centred against a block they do not match.
              isThreeLine: subtitle?.contains('\n') ?? false,
              trailing: trailing,
              onTap: () => showDocumentSheet(
                context,
                title: sheetTitle ?? title,
                subtitle: data['id']?.toString(),
                data: data,
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Copies [rows] to the clipboard as tab-separated values.
///
/// Deliberately not a file download: the app has no cross-platform save path
/// that works on web and mobile alike, and pasting into a spreadsheet covers
/// what someone actually wants from an export here.
Future<void> copyRowsAsTsv(
  BuildContext context, {
  required List<String> headers,
  required List<List<String>> rows,
}) async {
  final buffer = StringBuffer()..writeln(headers.join('\t'));
  for (final row in rows) {
    buffer.writeln(row.map((c) => c.replaceAll('\t', ' ')).join('\t'));
  }
  await Clipboard.setData(ClipboardData(text: buffer.toString()));
  if (context.mounted) {
    showSuccessSnackBar(context, 'Copied ${rows.length} rows to the clipboard');
  }
}

/// A labelled bar showing usage against a cap.
class ConsoleMeter extends StatelessWidget {
  const ConsoleMeter({
    super.key,
    required this.label,
    required this.valueText,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String valueText;

  /// Null when nothing caps this figure — the bar is then omitted entirely
  /// rather than drawn full or empty, both of which would be a lie.
  final double? fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                valueText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: fraction == null
                ? Container(
                    height: 7,
                    color: AppTheme.dividerC(context).withValues(alpha: 0.4),
                  )
                : TweenAnimationBuilder<double>(
                    // Animated so a limit moving after a plan change reads as a
                    // change rather than a redraw.
                    tween: Tween(begin: 0, end: fraction),
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 7,
                      backgroundColor: AppTheme.dividerC(
                        context,
                      ).withValues(alpha: 0.4),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A section heading inside a console page.
class ConsoleSectionTitle extends StatelessWidget {
  const ConsoleSectionTitle({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.color,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  /// Accent for the icon chip. Defaults to the console's info blue.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.infoColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 12),
      child: Row(
        children: [
          if (icon != null) ...[
            // A tinted chip rather than a bare grey glyph: it gives each
            // section a colour to be recognised by when scanning the page.
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null) Flexible(child: trailing!),
        ],
      ),
    );
  }
}
