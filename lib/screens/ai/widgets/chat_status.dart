import 'package:flutter/material.dart';

import '../../../config/motion.dart';
import '../../../config/theme.dart';

/// What the assistant is doing, as it does it.
///
/// Every line here came from the backend's `status` stream. That matters: the
/// widget this replaces displayed a canned reasoning log — "Initializing
/// semantic query embedding…", "Executing atomic transaction…" — chosen by
/// keyword-matching the user's question, describing work that never happened,
/// while the genuine frames were being discarded by the client.
///
/// So the rule this widget follows is: **it shows the steps it was given, and
/// nothing else.** [steps] accumulates as frames arrive; everything before the
/// last one is finished by definition, because the backend only sends the next
/// status once it has moved on. When no frames arrive at all — deterministic
/// and cached answers never pass through a model, so they send none — it falls
/// back to a single neutral line rather than inventing a plausible one.
class ChatStatusIndicator extends StatelessWidget {
  const ChatStatusIndicator({super.key, this.steps = const []});

  /// Backend status lines, oldest first.
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final done = steps.length > 1 ? steps.sublist(0, steps.length - 1) : const <String>[];
    final current = steps.isEmpty ? null : steps.last;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in done)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _StepRow(
                label: step,
                icon: Icons.check_rounded,
                color: AppTheme.success(context),
                muted: true,
              ),
            ),
          _ActiveStep(label: current),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.icon,
    required this.color,
    this.muted = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 16, child: Icon(icon, size: 13, color: color)),
        const SizedBox(width: AppTheme.spacingMD),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: muted
                      ? AppTheme.textMute(context)
                      : AppTheme.textSec(context),
                ),
          ),
        ),
      ],
    );
  }
}

/// The step in progress: three dots that travel, and the backend's own wording.
class _ActiveStep extends StatefulWidget {
  const _ActiveStep({required this.label});

  final String? label;

  @override
  State<_ActiveStep> createState() => _ActiveStepState();
}

class _ActiveStepState extends State<_ActiveStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary(context);
    final reduce = reduceMotion(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 16,
          height: 18,
          child: reduce
              ? Icon(Icons.more_horiz_rounded, size: 13, color: accent)
              : AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (i) {
                      // Each dot peaks a third of a cycle after the last, so
                      // the group reads as motion rather than a blink.
                      final phase = (_c.value - i * 0.22) % 1.0;
                      final lift = phase < 0.5
                          ? Curves.easeOut.transform(phase * 2)
                          : Curves.easeIn.transform(1 - (phase - 0.5) * 2);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 0.7),
                        child: Container(
                          width: 3.5,
                          height: 3.5,
                          margin: EdgeInsets.only(bottom: 4 * lift),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.45 + 0.55 * lift),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
        ),
        const SizedBox(width: AppTheme.spacingMD),
        Expanded(
          child: AnimatedSwitcher(
            duration:
                reduce ? Duration.zero : const Duration(milliseconds: 220),
            child: Text(
              // Neutral, not a fabricated step.
              widget.label ?? 'Thinking…',
              key: ValueKey(widget.label ?? ''),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSec(context),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}
