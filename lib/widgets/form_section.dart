import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'animations.dart';
import 'glass_panel.dart';

/// A titled group of form fields.
///
/// The stock forms each hand-rolled one flat `Form > Column` inside a single
/// panel, so a seven-field screen read as an undifferentiated wall. Grouping
/// them into named sections is the difference between a form you scan and a
/// form you wade through.
///
/// Pass [index] when several sections sit in a column so they stagger in.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.accent,
    this.trailing,
    this.index = 0,
    this.gap = AppTheme.spacingMD,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Colour for the icon chip. Defaults to the brand primary.
  final Color? accent;

  final Widget? trailing;
  final List<Widget> children;
  final int index;

  /// Vertical space inserted between [children].
  final double gap;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.primary(context);

    return FadeSlideIn(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.spacingLG),
        child: GlassPanel(
          padding: const EdgeInsets.all(AppTheme.spacingLG),
          borderRadius: AppTheme.radiusLG,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.tint(context, color),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, size: 17, color: color),
                    ),
                    const SizedBox(width: AppTheme.spacingMD),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) Flexible(child: trailing!),
                ],
              ),
              const SizedBox(height: AppTheme.spacingLG),
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
