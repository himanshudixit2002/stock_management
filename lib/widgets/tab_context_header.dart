import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/feature_map.dart';
import '../config/motion.dart';
import '../config/theme.dart';
import '../utils/responsive.dart';

/// A single, compact primary header for a tab shell. Replaces the older stacked
/// "app bar + contextual header + toolbar" model with one ~52px row:
/// a tinted leading icon, a title (+ optional badge), and trailing action
/// icons. When [subtitle] or [shortcuts] are supplied, the row becomes
/// collapsible — tapping the chevron reveals the subtitle and a horizontal
/// strip of shortcut chips. Honors reduce-motion and keeps >=44px tap targets.
///
/// Pure UI/navigation: shortcut chips push their existing route and never alter
/// providers, permissions, or route names.
class CompactTabHeader extends StatefulWidget {
  final IconData icon;
  final String title;

  /// Revealed (with [shortcuts]) when the header is expanded. When both this
  /// and [shortcuts] are empty the header is a fixed, non-collapsible row.
  final String? subtitle;

  /// Optional small count/label badge shown next to the title.
  final String? badge;
  final Color? badgeColor;

  /// Trailing action widgets (usually [IconButton]s / [PopupMenuButton]s).
  final List<Widget> actions;

  /// Already permission-filtered shortcut entries (see
  /// [FeatureMap.visibleEntriesFor]); revealed when expanded.
  final List<FeatureEntry> shortcuts;

  final bool initiallyExpanded;
  final EdgeInsetsGeometry? padding;

  /// Optional tap handler for the leading icon (e.g. open a related sheet).
  final VoidCallback? onLeadingTap;

  const CompactTabHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.badge,
    this.badgeColor,
    this.actions = const [],
    this.shortcuts = const [],
    this.initiallyExpanded = false,
    this.padding,
    this.onLeadingTap,
  });

  bool get _canExpand =>
      (subtitle != null && subtitle!.isNotEmpty) || shortcuts.isNotEmpty;

  @override
  State<CompactTabHeader> createState() => _CompactTabHeaderState();
}

class _CompactTabHeaderState extends State<CompactTabHeader> {
  late bool _expanded = widget.initiallyExpanded && widget._canExpand;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final hPad = Responsive.horizontalPadding(context);
    final reduce = reduceMotion(context);
    final badgeColor = widget.badgeColor ?? AppTheme.primaryColor;

    final leadingIcon = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(widget.icon, color: AppTheme.primaryColor, size: 18),
    );

    final row = SizedBox(
      height: 52,
      child: Row(
        children: [
          if (widget.onLeadingTap != null)
            Semantics(
              button: true,
              child: InkWell(
                onTap: widget.onLeadingTap,
                borderRadius: BorderRadius.circular(10),
                child: leadingIcon,
              ),
            )
          else
            leadingIcon,
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPri(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.badge != null && widget.badge!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.badge!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: badgeColor,
                ),
              ),
            ),
          ],
          const Spacer(),
          ...widget.actions,
          if (widget._canExpand)
            IconButton(
              onPressed: _toggle,
              tooltip: _expanded ? 'Show less' : 'Show more',
              visualDensity: VisualDensity.compact,
              icon: AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.iconMute(context),
                ),
              ),
            ),
        ],
      ),
    );

    final expandedContent = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 8),
              child: Text(
                widget.subtitle!,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSec(context),
                ),
              ),
            ),
          if (widget.shortcuts.isNotEmpty)
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: Responsive.scrollPhysics(context),
                itemCount: widget.shortcuts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) =>
                    _ShortcutChip(entry: widget.shortcuts[i]),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: widget.padding ?? EdgeInsets.fromLTRB(hPad, 4, hPad, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: expandedContent,
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
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
