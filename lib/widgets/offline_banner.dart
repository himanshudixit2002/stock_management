import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/connectivity_provider.dart';
import '../config/motion.dart';
import '../config/theme.dart';
import 'animations.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isOffline = context.select<ConnectivityProvider, bool>(
      (p) => p.isOffline,
    );
    final banner = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.warningColor,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const PulsingDot(color: Colors.white, size: 7),
            const SizedBox(width: 8),
            const Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'You are offline — some features may be unavailable',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: !isOffline
          ? const SizedBox.shrink()
          : (reduceMotion(context)
                ? banner
                : banner
                      .animate()
                      .fadeIn(duration: const Duration(milliseconds: 250))
                      .moveY(
                        begin: -16,
                        end: 0,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                      )),
    );
  }
}
