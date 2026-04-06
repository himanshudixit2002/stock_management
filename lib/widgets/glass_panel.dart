import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';
import '../utils/responsive.dart';

/// A frosted glass panel using BackdropFilter for liquid glass effect.
/// On native platforms, skips BackdropFilter to avoid black backdrop artifacts.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double? blurSigma;
  final EdgeInsetsGeometry? padding;
  final Border? border;

  /// When true, uses higher opacity for text-heavy content (WCAG contrast).
  final bool useContentVariant;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.blurSigma,
    this.padding,
    this.border,
    this.useContentVariant = false,
  });

  @override
  Widget build(BuildContext context) {
    final sigma = blurSigma ?? 4.0;
    final surface = useContentVariant
        ? (kIsWeb ? AppTheme.glassContent(context) : AppTheme.surface(context))
        : (kIsWeb ? AppTheme.glassSurface(context) : AppTheme.surface(context));
    final borderColor = useContentVariant
        ? AppTheme.glassBorderCont(context)
        : (kIsWeb ? AppTheme.glassBorder(context) : AppTheme.dividerC(context));

    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(color: borderColor, width: 1),
        boxShadow: kIsWeb ? null : (AppTheme.isDark(context) ? [] : AppTheme.cardShadow),
      ),
      child: child,
    );

    if (kIsWeb) {
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: container,
          ),
        ),
      );
    }
    return RepaintBoundary(child: container);
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
    final sigma = 4.0;
    final surface = widget.useContentVariant
        ? (kIsWeb ? AppTheme.glassContent(context) : AppTheme.surface(context))
        : (kIsWeb ? AppTheme.glassSurface(context) : AppTheme.surface(context));
    final baseBorderColor = widget.useContentVariant
        ? AppTheme.glassBorderCont(context)
        : (kIsWeb ? AppTheme.glassBorder(context) : AppTheme.dividerC(context));

    final borderColor = (kIsWeb && _isHovered && widget.onTap != null)
        ? AppTheme.primaryColor.withValues(alpha: 0.5)
        : baseBorderColor;

    final container = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: borderColor, width: _isHovered && kIsWeb ? 1.5 : 1),
        boxShadow: kIsWeb
            ? (_isHovered && widget.onTap != null
                ? [BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))]
                : null)
            : (AppTheme.isDark(context) ? [] : AppTheme.cardShadow),
      ),
      child: widget.child,
    );

    final Widget panel;
    if (kIsWeb) {
      panel = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: container,
        ),
      );
    } else {
      panel = container;
    }

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
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
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
    final sigma = 4.0;

    final content = Container(
      decoration: BoxDecoration(
        color: kIsWeb ? AppTheme.glassContent(context) : AppTheme.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorderCont(context), width: 1),
        boxShadow: kIsWeb ? null : (AppTheme.isDark(context) ? [] : AppTheme.cardShadow),
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

    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: content,
        ),
      );
    }
    return content;
  }
}
