import 'package:flutter/material.dart';
import 'reports_screen.dart';

/// Direct tab wrapper delivering 0ms instant load performance when navigating
/// to the Reports section.
class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReportsScreen();
  }
}
