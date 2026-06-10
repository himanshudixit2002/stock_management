import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Renders themed illustration compositions for specific icon contexts.
class _IllustratedIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;

  const _IllustratedIcon({
    required this.icon,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Icons.inventory_2 (any variant): box icon with sparkle icons around it
    if (_isInventoryIcon(icon)) {
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: size, color: color),
          ..._sparkleOffsets(size).map(
            (o) => Positioned(
              left: size * 0.5 + o.dx,
              top: size * 0.5 + o.dy,
              child: Icon(
                Icons.auto_awesome,
                size: size * 0.2,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      );
    }
    // Icons.history (any variant): clock with small arrow icons
    if (_isHistoryIcon(icon)) {
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: size, color: color),
          ..._arrowOffsets(size).map(
            (o) => Positioned(
              left: size * 0.5 + o.dx,
              top: size * 0.5 + o.dy,
              child: Icon(
                Icons.arrow_upward_rounded,
                size: size * 0.18,
                color: color.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      );
    }
    // Icons.local_shipping (any variant): truck with question mark
    if (_isShippingIcon(icon)) {
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: size, color: color),
          Positioned(
            right: -size * 0.05,
            top: -size * 0.05,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Text(
                '?',
                style: TextStyle(
                  color: color,
                  fontSize: size * 0.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }
    // Default: single icon
    return Icon(icon, size: size, color: color);
  }

  bool _isInventoryIcon(IconData i) =>
      i == Icons.inventory_2 ||
      i == Icons.inventory_2_outlined ||
      i == Icons.inventory_2_rounded;

  bool _isHistoryIcon(IconData i) =>
      i == Icons.history || i == Icons.history_rounded;

  bool _isShippingIcon(IconData i) =>
      i == Icons.local_shipping ||
      i == Icons.local_shipping_outlined ||
      i == Icons.local_shipping_rounded;

  List<Offset> _sparkleOffsets(double size) => [
    Offset(-size * 0.4, -size * 0.35),
    Offset(size * 0.35, -size * 0.4),
    Offset(size * 0.4, size * 0.3),
    Offset(-size * 0.35, size * 0.35),
  ];

  List<Offset> _arrowOffsets(double size) => [
    Offset(-size * 0.32, size * 0.2),
    Offset(size * 0.25, -size * 0.3),
  ];
}

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? buttonText;
  final VoidCallback? onButtonPressed;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.buttonText,
    this.onButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: _IllustratedIcon(
                icon: icon,
                size: 56,
                color: AppTheme.emptyIcon(context),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textPri(context),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSec(context),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (buttonText != null && onButtonPressed != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onButtonPressed,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(buttonText!),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
