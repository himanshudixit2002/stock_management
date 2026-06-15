import 'package:flutter/material.dart';
// Lottie is deferred so it is split into its own chunk and kept out of the
// main entrypoint. On web it is only fetched when this splash actually mounts
// (mobile/desktop only); on web the bootstrap uses a plain gradient instead.
import 'package:lottie/lottie.dart' deferred as lottie;

/// Animated brand mark shown on the native (non-web) startup splash.
///
/// Loads the deferred `lottie` library on first build and shows a lightweight
/// logo fallback while it loads or if it fails — so the splash always renders
/// instantly and the heavy animation library never lands in the main bundle.
class BrandedSplashLogo extends StatefulWidget {
  final double size;
  const BrandedSplashLogo({super.key, this.size = 120});

  @override
  State<BrandedSplashLogo> createState() => _BrandedSplashLogoState();
}

class _BrandedSplashLogoState extends State<BrandedSplashLogo> {
  late final Future<void> _load = lottie.loadLibrary();

  Widget _fallback() => Image.asset(
    'logo.png',
    width: widget.size,
    height: widget.size,
    fit: BoxFit.contain,
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FutureBuilder<void>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              snapshot.hasError) {
            return _fallback();
          }
          return lottie.Lottie.asset(
            'assets/lottie/lottie_logo.json',
            errorBuilder: (context, error, stackTrace) => _fallback(),
          );
        },
      ),
    );
  }
}
