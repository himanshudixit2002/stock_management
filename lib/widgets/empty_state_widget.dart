import 'package:flutter/material.dart';
// Deferred so the (rarely used) Lottie illustration path doesn't pull the
// animation library into the main bundle; callers without a lottieAsset never
// fetch it, and the illustrated icon is shown while it loads.
import 'package:lottie/lottie.dart' deferred as lottie;
import '../config/motion.dart';
import '../config/theme.dart';
import 'animations.dart';

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

  /// Optional Lottie animation asset (e.g. 'assets/lottie/empty.json'). When
  /// provided it replaces the illustrated icon; if the asset is missing/fails
  /// to load it silently falls back to the icon illustration.
  final String? lottieAsset;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.buttonText,
    this.onButtonPressed,
    this.lottieAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleFadeIn(child: _buildVisual(context)),
            const SizedBox(height: 16),
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.textPri(context),
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 180),
                child: Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSec(context),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (buttonText != null && onButtonPressed != null) ...[
              const SizedBox(height: 20),
              FadeSlideIn(
                delay: const Duration(milliseconds: 240),
                child: ShimmerButton(
                  label: buttonText!,
                  onPressed: onButtonPressed,
                  icon: Icons.add_rounded,
                  fullWidth: false,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVisual(BuildContext context) {
    final illustration = Container(
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
    );

    if (lottieAsset == null) return illustration;
    return SizedBox(
      height: 140,
      child: _DeferredLottie(
        asset: lottieAsset!,
        animate: !reduceMotion(context),
        fallback: illustration,
      ),
    );
  }
}

/// Loads the deferred `lottie` library on demand and renders the animation,
/// showing [fallback] while the library loads or if it (or the asset) fails.
class _DeferredLottie extends StatefulWidget {
  final String asset;
  final bool animate;
  final Widget fallback;

  const _DeferredLottie({
    required this.asset,
    required this.animate,
    required this.fallback,
  });

  @override
  State<_DeferredLottie> createState() => _DeferredLottieState();
}

class _DeferredLottieState extends State<_DeferredLottie> {
  late final Future<void> _load = lottie.loadLibrary();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError) {
          return widget.fallback;
        }
        return lottie.Lottie.asset(
          widget.asset,
          fit: BoxFit.contain,
          animate: widget.animate,
          errorBuilder: (context, error, stackTrace) => widget.fallback,
        );
      },
    );
  }
}
