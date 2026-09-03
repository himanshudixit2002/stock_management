import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'animations.dart';
import 'glass_panel.dart';

/// A single headline number with a label.
///
/// There were two different private `_StatCard`s in the app — one on Home, a
/// second, unrelated one on the dashboard — plus several one-off stat rows.
/// This is the shared one.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.caption,
    this.onTap,
    this.index = 0,
    this.dense = false,
    this.animateValue = true,
  });

  final String label;

  /// Pre-formatted, so callers keep control of currency and compaction.
  final String value;

  final IconData icon;
  final Color? color;

  /// Optional secondary line — a delta, a share, a timeframe.
  final String? caption;

  final VoidCallback? onTap;
  final int index;

  /// Lays the icon beside the number instead of above it, for 2-up grids.
  final bool dense;

  /// Counts the number up on first paint when it parses as a number.
  final bool animateValue;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.primary(context);
    final numeric = animateValue
        ? double.tryParse(value.replaceAll(RegExp(r'[^0-9.\-]'), ''))
        : null;

    final valueText = numeric != null && numeric.abs() < 1e9
        ? CountUpText(
            numeric,
            // Keeps whatever prefix/suffix the caller formatted around the
            // number — a currency symbol, a percent sign.
            formatter: (v) => value.replaceFirst(
              RegExp(r'[0-9][0-9,\.]*'),
              v.toStringAsFixed(0),
            ),
            style: Theme.of(context).textTheme.headlineMedium,
          )
        : Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium,
          );

    final iconChip = Container(
      width: dense ? 34 : 38,
      height: dense ? 34 : 38,
      decoration: BoxDecoration(
        color: AppTheme.tint(context, accent),
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: dense ? 17 : 19, color: accent),
    );

    final labelText = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium,
    );

    return FadeSlideIn(
      index: index,
      child: GlassCard(
        onTap: onTap,
        borderRadius: AppTheme.radiusLG,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingLG),
          child: dense
              ? Row(
                  children: [
                    iconChip,
                    const SizedBox(width: AppTheme.spacingMD),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [valueText, labelText],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        iconChip,
                        const Spacer(),
                        if (onTap != null)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: AppTheme.iconMute(context),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingMD),
                    valueText,
                    labelText,
                    if (caption != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: accent, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
