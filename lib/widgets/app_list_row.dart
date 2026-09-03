import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'animations.dart';
import 'glass_panel.dart';

/// A tappable row inside a panel.
///
/// Replaces the raw `ListTile`s scattered through reports, settings and roles.
/// Two things it fixes over a bare tile:
///
/// * the ink splash lands *on* the panel. `GlassPanel` is an opaque container
///   with no `Material` of its own, so a tile inside one splashed behind it and
///   the row looked unresponsive;
/// * the leading icon gets a tinted chip, which is what gives a list of rows a
///   scannable left edge instead of a column of identical grey glyphs.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accent,
    this.trailing,
    this.onTap,
    this.index = 0,
    this.showChevron = true,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? accent;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int index;
  final bool showChevron;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppTheme.primary(context);

    return FadeSlideIn(
      index: index,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
        child: GlassPanel(
          borderRadius: AppTheme.radiusMD,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                onTap: onTap,
                dense: dense,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingLG,
                  vertical: dense ? 2 : AppTheme.spacingXS,
                ),
                leading: icon == null
                    ? null
                    : Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.tint(context, color),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSM,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(icon, size: 19, color: color),
                      ),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle: subtitle == null
                    ? null
                    : Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                isThreeLine: subtitle?.contains('\n') ?? false,
                trailing: trailing ??
                    (onTap != null && showChevron
                        ? Icon(
                            Icons.chevron_right_rounded,
                            color: AppTheme.iconMute(context),
                          )
                        : null),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
