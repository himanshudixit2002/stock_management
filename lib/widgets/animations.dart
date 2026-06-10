import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/motion.dart';

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
