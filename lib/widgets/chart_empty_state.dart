import 'package:flutter/material.dart';
import '../config/theme.dart';

class ChartEmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const ChartEmptyState({
    super.key,
    this.message = 'No data available',
    this.icon = Icons.bar_chart_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = (constraints.maxWidth * 0.5).clamp(180.0, 300.0);
        return SizedBox(
          height: h,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 40,
                  color: AppTheme.emptyIcon(context),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: TextStyle(
                    color: AppTheme.textSec(context),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
