import 'package:flutter/material.dart';

/// The app's brand mark.
///
/// Always render the logo through this widget. It points at
/// `assets/images/logo.png` — a 384px copy that covers the largest on-screen
/// size (120dp) at 3x with no upscaling. The 3.9MB `logo.png` at the repo root
/// is the `flutter_launcher_icons` source only; it is deliberately not bundled,
/// because shipping it cost a cold web visitor ~4MB to draw a 44px mark and
/// decoded to ~18MB of memory on device.
///
/// [cacheWidth]/[cacheHeight] are set from the display size so the decoded
/// bitmap stays proportional to what is actually painted.
class BrandLogo extends StatelessWidget {
  final double size;
  final BoxFit fit;

  const BrandLogo({super.key, required this.size, this.fit = BoxFit.contain});

  static const String assetPath = 'assets/images/logo.png';

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final cache = (size * ratio).round();
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: fit,
      cacheWidth: cache,
      cacheHeight: cache,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Static brand mark shown on the startup splash.
class BrandedSplashLogo extends StatelessWidget {
  final double size;
  const BrandedSplashLogo({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) => BrandLogo(size: size);
}
