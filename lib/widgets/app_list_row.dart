import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/motion.dart';
import '../config/theme.dart';
import '../utils/dialogs.dart';
import 'animations.dart';
import 'glass_panel.dart';

/// Minimum row height, comfortable and compact.
///
/// Both clear `Responsive.minTouchTargetSize` (44). The settings rows this
/// replaces were `ListTile`s with `dense: true`, `VisualDensity(vertical: -1)`
/// and one logical pixel of vertical padding, so their height depended on
/// whether a subtitle happened to be present and the shortest of them fell
/// under the touch target the rest of the app holds itself to.
const double kAppRowMinHeight = 56;
const double kAppRowMinHeightDense = 48;

/// A tappable row inside a panel.
///
/// Replaces the raw `ListTile`s scattered through reports, settings and roles.
/// Two things it fixes over a bare tile:
///
/// * the ink splash lands *on* the panel. `GlassPanel` is an opaque container
///   with no `Material` of its own, so a tile inside one splashed behind it and
///   the row looked unresponsive;
/// * the leading icon gets a tinted chip, which is what gives a list of rows a
///   scannable left edge instead of a column of identical grey glyphs.
///
/// Type comes from the theme (`titleMedium` / `bodySmall`) and the chip fill
/// from [AppTheme.tint], so a row reads the same as every other list in the app
/// and its dark mode is not a hardcoded light-mode alpha.
class AppListRow extends StatefulWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accent,
    this.trailing,
    this.onTap,
    this.index = 0,
    this.showChevron = true,
    this.dense = false,
    this.highlighted = false,
    this.enabled = true,
    this.semanticLabel,
  });

  final String title;

  /// The second line. On a settings hub this is the row's live state — "Dark ·
  /// 6 quick actions" — which is what lets a category row answer a question
  /// without being opened.
  final String? subtitle;

  final IconData? icon;
  final Color? accent;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int index;
  final bool showChevron;
  final bool dense;

  /// Paints the accent tint and border, for a moment, so a row arrived at from
  /// search is visibly the one that was asked for.
  final bool highlighted;

  final bool enabled;
  final String? semanticLabel;

  @override
  State<AppListRow> createState() => _AppListRowState();
}

class _AppListRowState extends State<AppListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.accent ?? AppTheme.primary(context);
    final reduce = reduceMotion(context);
    final tappable = widget.enabled && widget.onTap != null;

    Widget row = AnimatedContainer(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: widget.highlighted
            ? AppTheme.tint(context, color)
            : (_hover ? AppTheme.hoverTint(context) : Colors.transparent),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(
          color: widget.highlighted
              ? color.withValues(alpha: 0.45)
              : Colors.transparent,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: tappable ? widget.onTap : null,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: widget.dense
                  ? kAppRowMinHeightDense
                  : kAppRowMinHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingLG,
                vertical: AppTheme.spacingSM,
              ),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    _RowChip(icon: widget.icon!, color: color),
                    const SizedBox(width: AppTheme.spacingMD),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textSec(context)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: AppTheme.spacingSM),
                    widget.trailing!,
                  ] else if (tappable && widget.showChevron)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppTheme.iconMute(context),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (kIsWeb && tappable) {
      row = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: row,
      );
    }

    return FadeSlideIn(
      // Capped: a hub of nine rows at the 55ms stagger interval would take
      // half a second to finish arriving.
      index: widget.index.clamp(0, 5),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
        child: Semantics(
          label: widget.semanticLabel,
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.5,
            child: GlassPanel(
              borderRadius: AppTheme.radiusMD,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A switch on the same geometry as [AppListRow], so a list mixing the two
/// keeps one rhythm.
///
/// [onChanged] returns whether the write succeeded. While it is in flight the
/// switch is replaced by a spinner and further taps are ignored — the toggles
/// this replaces were optimistic with a silent rollback, so a failed write
/// looked like a switch that flicked back on its own.
class AppSwitchRow extends StatefulWidget {
  const AppSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.accent,
    this.index = 0,
    this.enabled = true,
    this.highlighted = false,
    this.errorText,
    this.disabledReason,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? accent;
  final bool value;

  /// Returns true when the change stuck.
  final Future<bool> Function(bool) onChanged;

  final int index;
  final bool enabled;
  final bool highlighted;

  /// Message shown when [onChanged] reports failure.
  final String Function()? errorText;

  /// Why the row is not interactive, shown in place of the subtitle.
  final String? disabledReason;

  @override
  State<AppSwitchRow> createState() => _AppSwitchRowState();
}

class _AppSwitchRowState extends State<AppSwitchRow> {
  bool _pending = false;

  Future<void> _toggle(bool next) async {
    if (_pending || !widget.enabled) return;
    setState(() => _pending = true);
    final ok = await widget.onChanged(next);
    if (!mounted) return;
    setState(() => _pending = false);
    if (!ok) {
      showErrorSnackBar(
        context,
        widget.errorText?.call() ?? 'Could not save that. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accent ?? AppTheme.primary(context);
    final interactive = widget.enabled && !_pending;
    final subtitle = widget.disabledReason ?? widget.subtitle;

    return FadeSlideIn(
      index: widget.index.clamp(0, 5),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.spacingSM),
        child: GlassPanel(
          borderRadius: AppTheme.radiusMD,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusMD),
            child: AnimatedContainer(
              duration: reduceMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: widget.highlighted
                    ? AppTheme.tint(context, color)
                    : Colors.transparent,
                border: Border.all(
                  color: widget.highlighted
                      ? color.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: interactive ? () => _toggle(!widget.value) : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: kAppRowMinHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingLG,
                        vertical: AppTheme.spacingSM,
                      ),
                      child: Row(
                        children: [
                          if (widget.icon != null) ...[
                            _RowChip(
                              icon: widget.icon!,
                              color: color,
                              // The chip keeps its tint whether the switch is
                              // on or off. Fading it with the value read as a
                              // disabled row when the switch already says what
                              // the state is.
                              iconColor: widget.value
                                  ? color
                                  : AppTheme.iconMute(context),
                            ),
                            const SizedBox(width: AppTheme.spacingMD),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: AppTheme.textSec(context),
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacingSM),
                          SizedBox(
                            width: 44,
                            height: 32,
                            child: Center(
                              child: _pending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Switch(
                                      value: widget.value,
                                      activeTrackColor: color,
                                      onChanged: interactive ? _toggle : null,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tinted square behind a row's icon — the thing that gives a column of
/// rows a scannable left edge.
class _RowChip extends StatelessWidget {
  const _RowChip({required this.icon, required this.color, this.iconColor});

  final IconData icon;
  final Color color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.tint(context, color),
        borderRadius: BorderRadius.circular(AppTheme.radiusSM),
      ),
      child: Icon(icon, size: 19, color: iconColor ?? color),
    );
  }
}
