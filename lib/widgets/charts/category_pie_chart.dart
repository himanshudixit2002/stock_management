import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../chart_empty_state.dart';
import '../../config/theme.dart';

class CategoryPieChart extends StatefulWidget {
  final Map<String, double> data; // categoryName -> value
  final String valueLabel; // e.g. 'products', 'value'
  final bool isCurrency;

  const CategoryPieChart({
    super.key,
    required this.data,
    this.valueLabel = '',
    this.isCurrency = false,
  });

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  int _touchedIndex = -1;

  static const List<Color> _colors = [
    AppTheme.primaryColor,
    AppTheme.accentColor,
    AppTheme.successColor,
    AppTheme.warningColor,
    AppTheme.dangerColor,
    AppTheme.infoColor,
    Color(0xFF7E57C2),
    Color(0xFF26A69A),
    Color(0xFFEC407A),
    Color(0xFF8D6E63),
    Color(0xFF78909C),
    Color(0xFFD4E157),
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty || widget.data.values.every((v) => v == 0)) {
      return const ChartEmptyState();
    }

    final entries = widget.data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartH = (constraints.maxWidth * 0.5).clamp(180.0, 300.0);
        return Column(
          children: [
            SizedBox(
              height: chartH,
              child: PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (event, pieTouchResponse) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          _touchedIndex = -1;
                          return;
                        }
                        _touchedIndex = pieTouchResponse
                            .touchedSection!
                            .touchedSectionIndex;
                      });
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: List.generate(entries.length, (i) {
                    final isTouched = i == _touchedIndex;
                    final entry = entries[i];
                    final pct = (entry.value / total * 100).toStringAsFixed(1);
                    return PieChartSectionData(
                      color: _colors[i % _colors.length],
                      value: entry.value,
                      title: isTouched ? '$pct%' : '',
                      radius: isTouched ? 55 : 45,
                      titleStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: List.generate(entries.length, (i) {
                final entry = entries[i];
                final valStr = widget.isCurrency
                    ? '${AppTheme.currencySymbol}${entry.value.toStringAsFixed(0)}'
                    : entry.value.toStringAsFixed(0);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _colors[i % _colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${entry.key} ($valStr)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        );
      },
    );
  }
}
