import 'package:flutter/material.dart';
import '../config/theme.dart';

class ChartEmptyState extends StatelessWidget {
  final String message;

  const ChartEmptyState({super.key, this.message = 'No data available'});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = (constraints.maxWidth * 0.5).clamp(180.0, 300.0);
        return SizedBox(
          height: h,
          child: Center(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        );
      },
    );
  }
}
