import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../widgets/shimmer_loading.dart';
// The Reports screen (and its fl_chart + excel dependencies) is heavy, so it is
// deferred into its own chunk and only fetched the first time the Reports tab
// is actually opened — keeping it out of the main startup bundle.
import 'reports_screen.dart' deferred as reports;

/// Tab-shell wrapper that lazily loads the deferred Reports library on first
/// build, showing a layout-matched shimmer while the chunk downloads. Used as
/// the Reports tab body so charts never load until the user opens Reports.
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  late final Future<void> _load = reports.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: AppTheme.bg(context),
            appBar: AppBar(title: const Text('Reports')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppTheme.dangerColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load Reports',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPri(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSec(context)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: AppTheme.bg(context),
            appBar: AppBar(title: const Text('Reports')),
            body: const ShimmerLoading(layout: ShimmerLayout.card),
          );
        }
        return reports.ReportsScreen();
      },
    );
  }
}
