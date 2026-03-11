import 'package:flutter/material.dart';
import '../chart_empty_state.dart';
import '../../config/theme.dart';

class TopProductsChart extends StatelessWidget {
  final List<MapEntry<String, int>> data;
  final Color barColor;
  final String valueLabel;

  const TopProductsChart({
    super.key,
    required this.data,
    this.barColor = AppTheme.primaryColor,
    this.valueLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const ChartEmptyState();
    }

    final maxVal = data.first.value.toDouble();

    return Column(
      children: data.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final fraction = maxVal > 0 ? item.value / maxVal : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${idx + 1}.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: idx < 3
                        ? AppTheme.primaryColor
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  item.key,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Stack(
                  children: [
                    Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppTheme.dividerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.05, 1.0),
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: barColor.withValues(
                            alpha: 0.7 + 0.3 * (1 - idx / data.length),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                child: Text(
                  '${item.value}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
