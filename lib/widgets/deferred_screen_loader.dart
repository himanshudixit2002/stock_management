import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Shows a spinner while a `deferred` library downloads, then builds the screen.
///
/// Used by every deferred route so heavy, rarely-opened screens (Excel import,
/// the barcode scanner, POS, the AI assistant, reports) stay out of the initial
/// bundle. Lives here rather than in the router so non-route callers — the
/// Ask-AI launcher, the reports export sheet — can reuse it.
class DeferredScreenLoader extends StatelessWidget {
  final Future<void> future;
  final WidgetBuilder builder;
  const DeferredScreenLoader({
    super.key,
    required this.future,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: future,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Scaffold(
            backgroundColor: AppTheme.bg(ctx),
            appBar: AppBar(),
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
                      'Could not load this screen',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPri(ctx),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Check your connection and try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSec(ctx)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: AppTheme.bg(ctx),
            body: const Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          );
        }
        return builder(ctx);
      },
    );
  }
}
