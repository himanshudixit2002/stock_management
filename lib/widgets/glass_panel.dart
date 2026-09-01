import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/motion.dart';
import '../config/theme.dart';
import '../utils/responsive.dart';

/// A raised surface panel.
///
/// This used to apply a `BackdropFilter` frosted-glass blur on web (native
/// skipped it to avoid black backdrop artifacts). That was the app's single
/// largest source of web jank: on CanvasKit every `BackdropFilter` forces a
/// `saveLayer` and re-blurs everything painted behind it on each dirty frame,
/// and there are ~155 of these across the app — ten at once on a screen like
/// invoice detail. Web now renders the same opaque surface as native.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Border? border;

  /// When true, uses higher opacity for text-heavy content (WCAG contrast).
  final bool useContentVariant;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding,
    this.border,
    this.useContentVariant = false,
  });

  @override
  Widget build(BuildContext context) {
    final surface = useContentVariant
        ? AppTheme.glassContent(context)
        : AppTheme.surface(context);
    final borderColor = useContentVariant
        ? AppTheme.glassBorderCont(context)
        : AppTheme.dividerC(context);

    // No ClipRRect/BackdropFilter: an opaque, rounded DecoratedBox paints in a
    // single draw call with no saveLayer, where the blurred version cost a
    // full-region backdrop read + blur every frame the panel was dirty.
    return RepaintBoundary(
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(borderRadius),
          border: border ?? Border.all(color: borderColor, width: 1),
          boxShadow: AppTheme.isDark(context) ? [] : AppTheme.cardShadow,
        ),
        child: child,
      ),
    );
  }
}

/// Glass-style card for list/grid items with InkWell support.
/// Uses content variant by default for text readability.
/// Includes subtle scale-down press feedback when tappable.
class GlassCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final String? semanticLabel;

  /// When true (default), uses higher opacity for text readability.
  final bool useContentVariant;

  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = 16,
    this.useContentVariant = true,
    this.semanticLabel,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _isPressed = false;
  bool _isHovered = false;

  void _handleTapDown(TapDownDetails _) {
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails _) {
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.useContentVariant
        ? AppTheme.glassContent(context)
        : AppTheme.surface(context);
    final baseBorderColor = widget.useContentVariant
        ? AppTheme.glassBorderCont(context)
        : AppTheme.dividerC(context);

    final borderColor = (kIsWeb && _isHovered && widget.onTap != null)
        ? AppTheme.primaryColor.withValues(alpha: 0.5)
        : baseBorderColor;

    final container = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(
          color: borderColor,
          width: _isHovered && kIsWeb ? 1.5 : 1,
        ),
        boxShadow: (kIsWeb && _isHovered && widget.onTap != null)
            ? [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : (AppTheme.isDark(context) ? [] : AppTheme.cardShadow),
      ),
      child: widget.child,
    );

    // Opaque surface on every platform — see [GlassPanel] for why the web
    // BackdropFilter was removed. Cards are the worst case for it: they appear
    // many-per-screen inside scrolling lists, so every scroll frame re-blurred
    // the backdrop once per visible card.
    final Widget panel = container;

    if (widget.onTap != null) {
      final interactive = Semantics(
        button: true,
        label: widget.semanticLabel,
        child: GestureDetector(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          child: AnimatedScale(
            scale: _isPressed ? 0.97 : 1.0,
            duration: kPressDuration,
            curve: kPressCurve,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                },
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: panel,
              ),
            ),
          ),
        ),
      );

      if (kIsWeb) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: interactive,
        );
      }
      return interactive;
    }
    return widget.semanticLabel != null
        ? Semantics(label: widget.semanticLabel, child: panel)
        : panel;
  }
}

/// Section card with glass effect for Reports, Settings, forms, etc.
class GlassSectionCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? trailing;
  final IconData? icon;
  final Color? iconColor;

  const GlassSectionCard({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {

    final content = Container(
      decoration: BoxDecoration(
        color: kIsWeb
            ? AppTheme.glassContent(context)
            : AppTheme.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorderCont(context), width: 1),
        boxShadow: kIsWeb
            ? null
            : (AppTheme.isDark(context) ? [] : AppTheme.cardShadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((title != null && title!.isNotEmpty) || trailing != null) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                Responsive.cardPadding(context),
                12,
                Responsive.cardPadding(context),
                6,
              ),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 20,
                      color: iconColor ?? AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: title != null && title!.isNotEmpty
                        ? Text(
                            title!,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPri(context),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (trailing != null) ...[trailing!],
                ],
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.all(Responsive.cardPadding(context)),
            child: child,
          ),
        ],
      ),
    );

    // Opaque on web too — see [GlassPanel] for why the BackdropFilter went.
    return content;
  }
}
