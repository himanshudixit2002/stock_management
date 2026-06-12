import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/motion.dart';
import '../config/theme.dart';

/// Fades + slides a widget in on first build. Pass [index] to stagger many of
/// them (lists/grids). Honors reduce-motion: renders the final state instantly.
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration? duration;
  final Duration? delay;
  final double slideOffset;
  final Axis direction;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.duration,
    this.delay,
    this.slideOffset = kEntranceSlideOffset,
    this.direction = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    final dur = duration ?? kEntranceDuration;
    final effectiveDelay = delay ?? staggerDelay(index);
    final animated = child.animate(delay: effectiveDelay).fadeIn(
          duration: dur,
          curve: kEntranceCurve,
        );
    return direction == Axis.vertical
        ? animated.moveY(begin: slideOffset, end: 0, duration: dur, curve: kEntranceCurve)
        : animated.moveX(begin: slideOffset, end: 0, duration: dur, curve: kEntranceCurve);
  }
}

/// Fade + gentle scale-in, ideal for hero headers, icons and FABs.
class ScaleFadeIn extends StatelessWidget {
  final Widget child;
  final Duration? duration;
  final Duration? delay;
  final double beginScale;

  const ScaleFadeIn({
    super.key,
    required this.child,
    this.duration,
    this.delay,
    this.beginScale = 0.92,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    final dur = duration ?? kEntranceDuration;
    return child.animate(delay: delay ?? Duration.zero).fadeIn(duration: dur, curve: kEntranceCurve).scale(
          begin: Offset(beginScale, beginScale),
          end: const Offset(1, 1),
          duration: dur,
          curve: Curves.easeOutBack,
        );
  }
}

/// Animated number that counts up from 0 to [value] on first build.
/// Use [formatter] to control display (currency, decimals, suffixes).
class CountUpText extends StatelessWidget {
  final num value;
  final TextStyle? style;
  final String Function(num value)? formatter;
  final Duration? duration;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const CountUpText(
    this.value, {
    super.key,
    this.style,
    this.formatter,
    this.duration,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = formatter ?? (v) => v.round().toString();
    Widget textOf(num v) => Text(
          fmt(v),
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
        );
    if (reduceMotion(context) || value == 0) return textOf(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration ?? kCountUpDuration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => textOf(v),
    );
  }
}

/// A scaffold-friendly background whose gradient alignment drifts slowly for a
/// subtle "alive" feel. Honors reduce-motion (renders a static gradient).
class AnimatedGradientBackground extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  final Duration period;

  const AnimatedGradientBackground({
    super.key,
    required this.child,
    required this.colors,
    this.period = const Duration(seconds: 12),
  });

  @override
  State<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    // Only animate when motion is allowed; started in didChangeDependencies.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: widget.child,
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final begin = Alignment.lerp(
          Alignment.topLeft,
          Alignment.topRight,
          t,
        )!;
        final end = Alignment.lerp(
          Alignment.bottomRight,
          Alignment.bottomLeft,
          t,
        )!;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.colors,
              begin: begin,
              end: end,
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Wraps any [child] with a tactile press response: a subtle scale-down
/// ([kCardPressScale]) + [HapticFeedback.selectionClick] on tap, plus an
/// optional hover lift on web ([kHoverLiftOffset]). Honors reduce-motion by
/// dropping the scale/lift animation (the tap + haptic still fire).
class PlayfulPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  /// Lift the child slightly on hover (web only). Defaults to true.
  final bool enableHoverLift;

  const PlayfulPressable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.enableHoverLift = true,
  });

  @override
  State<PlayfulPressable> createState() => _PlayfulPressableState();
}

class _PlayfulPressableState extends State<PlayfulPressable> {
  bool _pressed = false;
  bool _hovered = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final interactive = widget.onTap != null;
    final radius = widget.borderRadius ?? BorderRadius.circular(16);

    final hoverLift =
        widget.enableHoverLift && kIsWeb && _hovered && interactive && !reduce
        ? -kHoverLiftOffset
        : 0.0;
    final scale = !reduce && _pressed && interactive ? kCardPressScale : 1.0;

    Widget result = AnimatedScale(
      scale: scale,
      duration: kPressDuration,
      curve: kPressCurve,
      child: AnimatedSlide(
        offset: Offset(0, hoverLift / 100),
        duration: kHoverDuration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );

    if (!interactive) return result;

    result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap!.call();
      },
      child: ClipRRect(borderRadius: radius, child: result),
    );

    if (kIsWeb) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: result,
      );
    }
    return result;
  }
}

/// A primary call-to-action button with a subtle hover shimmer sweep on web.
/// Falls back to a normally styled [ElevatedButton] when reduce-motion is on or
/// the platform is not web. Defaults to a 52px-high, full-width primary button.
class ShimmerButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool fullWidth;
  final double height;

  const ShimmerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = true,
    this.height = 52,
  });

  @override
  State<ShimmerButton> createState() => _ShimmerButtonState();
}

class _ShimmerButtonState extends State<ShimmerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);

    final child = widget.icon != null
        ? ElevatedButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon, size: 20),
            label: Text(widget.label),
            style: ElevatedButton.styleFrom(
              minimumSize: Size(widget.fullWidth ? double.infinity : 0, widget.height),
            ),
          )
        : ElevatedButton(
            onPressed: widget.onPressed,
            style: ElevatedButton.styleFrom(
              minimumSize: Size(widget.fullWidth ? double.infinity : 0, widget.height),
            ),
            child: Text(widget.label),
          );

    final button = SizedBox(
      width: widget.fullWidth ? double.infinity : null,
      height: widget.height,
      child: child,
    );

    if (!kIsWeb || reduce || widget.onPressed == null) {
      return button;
    }

    // Sweep a soft highlight across the button while hovered (web only).
    final sweep = _hovered
        ? button
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                duration: const Duration(milliseconds: 1400),
                color: Colors.white.withValues(alpha: 0.35),
              )
        : button;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: sweep,
    );
  }
}

/// A section title preceded by a small gradient accent bar, with an optional
/// [subtitle]. Wrapped in [FadeSlideIn] unless [animate] is false (or
/// reduce-motion is on, which [FadeSlideIn] already respects).
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool animate;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.animate = true,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: subtitle != null ? 34 : 18,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPri(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.textSec(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (!animate) return content;
    return FadeSlideIn(child: content);
  }
}

/// An icon centered inside a tinted circular badge, entering with a gentle
/// bounce ([ScaleFadeIn] / easeOutBack). Honors reduce-motion via [ScaleFadeIn].
class AnimatedIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const AnimatedIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleFadeIn(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      ),
    );
  }
}

/// A small live indicator that gently pulses (alerts / notifications / offline).
/// Renders a static dot when reduce-motion is on.
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulsingDot({super.key, this.color = AppTheme.dangerColor, this.size = 10});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kPulseDuration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _dot() => Container(
    width: widget.size,
    height: widget.size,
    decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
  );

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return _dot();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return SizedBox(
          width: widget.size * 2,
          height: widget.size * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.4,
                child: Container(
                  width: widget.size + widget.size * t,
                  height: widget.size + widget.size * t,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: _dot(),
    );
  }
}

/// A consistent bottom-sheet content wrapper: rounds the top corners (20px),
/// paints a themed surface + grab handle, and slides up with the spring curve
/// ([kSpringCurve]). Honors reduce-motion (renders in place). This is a content
/// wrapper only — it does not change how the sheet itself is presented.
class SlideUpSheet extends StatelessWidget {
  final Widget child;
  final String? title;

  /// When false, only the surface + handle styling is applied (no entrance).
  final bool animate;

  const SlideUpSheet({
    super.key,
    required this.child,
    this.title,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.dividerStrongC(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                title!,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPri(context),
                ),
              ),
            ),
          ],
          Flexible(child: child),
        ],
      ),
    );

    if (!animate || reduceMotion(context)) return surface;
    return surface
        .animate()
        .fadeIn(duration: kSheetDuration)
        .moveY(begin: 24, end: 0, duration: kSheetDuration, curve: kSpringCurve);
  }
}
