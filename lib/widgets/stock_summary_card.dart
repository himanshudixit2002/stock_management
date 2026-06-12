import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/motion.dart';
import '../config/theme.dart';
import 'animations.dart';
import 'glass_panel.dart';

class StockSummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  /// Position in a row/grid of cards; used to stagger the entrance animation.
  final int index;

  const StockSummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: color,
    );

    return ScaleFadeIn(
      delay: staggerDelay(index),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.coloredShadow(color),
        ),
        child: GlassCard(
          onTap: onTap,
          borderRadius: 20,
          child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: AppTheme.iconMute(context),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _buildValue(valueStyle),
              const SizedBox(height: 4),
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          ),
        ),
      ),
    );
  }

  /// Counts up plain integer values (optionally comma-grouped) for a lively
  /// dashboard feel; leaves formatted strings (currency, %, abbreviations)
  /// untouched so they always render correctly.
  Widget _buildValue(TextStyle? style) {
    final isSimpleInt = RegExp(r'^[0-9,]+$').hasMatch(value);
    final intVal = int.tryParse(value.replaceAll(',', ''));
    if (!isSimpleInt || intVal == null) {
      return Text(value, style: style);
    }
    final fmt = NumberFormat.decimalPattern();
    return CountUpText(
      intVal,
      style: style,
      formatter: (v) => fmt.format(v.round()),
    );
  }
}
