import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/promo_config_model.dart';
import '../providers/promo_provider.dart';
import 'animations.dart';

/// The founding-member offer, shown above the signed-out forms.
///
/// Renders nothing at all when there is no offer, it is switched off, or the
/// read failed — a promotion is decoration and must never sit between someone
/// and a signup.
///
/// The copy is intentionally careful: nothing here promises the offer *ends* at
/// the cap, because the cap is not enforced. Past it the message changes; what
/// a new workspace is granted does not. See [PromoConfig].
class PromoBanner extends StatefulWidget {
  const PromoBanner({super.key, this.compact = false});

  /// A one-line variant for screens where the offer is context, not the point.
  final bool compact;

  @override
  State<PromoBanner> createState() => _PromoBannerState();
}

class _PromoBannerState extends State<PromoBanner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PromoProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final promo = context.watch<PromoProvider>().visibleConfig;
    if (promo == null) return const SizedBox.shrink();

    return FadeSlideIn(
      child: widget.compact
          ? _CompactBanner(promo: promo)
          : _FullBanner(promo: promo),
    );
  }
}

class _FullBanner extends StatelessWidget {
  const _FullBanner({required this.promo});

  final PromoConfig promo;

  @override
  Widget build(BuildContext context) {
    final progress = promo.progress;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGrad(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        boxShadow: AppTheme.isDark(context)
            ? const []
            : [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A filled chip rather than a bare glyph: it anchors the headline
              // and survives the gradient behind it at small sizes.
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.onGradient.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(
                  promo.isFull
                      ? Icons.verified_rounded
                      : Icons.auto_awesome_rounded,
                  color: AppTheme.onGradient,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  promo.activeHeadline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppTheme.onGradient,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            promo.activeSubtext,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.onGradientMuted,
              height: 1.4,
            ),
          ),
          if (progress != null && !promo.isFull) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                // Fills on arrival: a static bar reads as a decoration, a
                // filling one reads as a cohort actually running out.
                tween: Tween(begin: 0, end: progress),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 7,
                  backgroundColor: AppTheme.onGradient.withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation(
                    AppTheme.onGradient,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${promo.claimedCount} of ${promo.capCount} claimed'
              '  ·  ${promo.remaining} left',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.onGradientMuted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactBanner extends StatelessWidget {
  const _CompactBanner({required this.promo});

  final PromoConfig promo;

  @override
  Widget build(BuildContext context) {
    // The theme-aware primary, not the constant: the light indigo is too dark
    // to read as an accent on a near-black surface.
    final accent = AppTheme.primary(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.tint(context, accent),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              promo.activeHeadline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
