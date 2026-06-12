import 'package:flutter/material.dart';

import 'empty_state_widget.dart';

/// A rich "not found" / missing-data state for detail screens, built on top of
/// [EmptyStateWidget] so it shares the app's illustrated empty-state styling.
///
/// Use this instead of a plain `Center(child: Text('... not found'))` to make
/// missing data feel intentional rather than broken.
class NotFoundState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  /// When provided, shows a primary "Retry" action.
  final VoidCallback? onRetry;

  /// When provided, shows a secondary "Go Back" action below the illustration.
  final VoidCallback? onGoBack;

  const NotFoundState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.search_off_rounded,
    this.onRetry,
    this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: EmptyStateWidget(
            icon: icon,
            title: title,
            subtitle: message,
            buttonText: onRetry != null ? 'Retry' : null,
            onButtonPressed: onRetry,
          ),
        ),
        if (onGoBack != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: TextButton.icon(
              onPressed: onGoBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Go Back'),
            ),
          ),
      ],
    );
  }
}
