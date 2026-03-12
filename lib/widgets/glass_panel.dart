import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
    final sigma = blurSigma ?? 10.0;
    final surface = useContentVariant
        ? (kIsWeb ? AppTheme.glassSurfaceContent : AppTheme.surfaceColor)
        : (kIsWeb ? AppTheme.glassSurfaceLight : AppTheme.surfaceColor);
    final borderColor = useContentVariant
        ? AppTheme.glassBorderContent
        : (kIsWeb ? AppTheme.glassBorderLight : AppTheme.dividerColor);

    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(color: borderColor, width: 1),
        boxShadow: kIsWeb ? null : AppTheme.cardShadow,
      ),
      child: child,
    );

    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: container,
        ),
      );
    }
    return container;
  }
}

/// Glass-style card for list/grid items with InkWell support.
/// Uses content variant by default for text readability.
class GlassCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final sigma = 10.0;
    final surface = useContentVariant
        ? (kIsWeb ? AppTheme.glassSurfaceContent : AppTheme.surfaceColor)
        : (kIsWeb ? AppTheme.glassSurfaceLight : AppTheme.surfaceColor);
    final borderColor = useContentVariant
        ? AppTheme.glassBorderContent
        : (kIsWeb ? AppTheme.glassBorderLight : AppTheme.dividerColor);

    final container = Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: kIsWeb ? null : AppTheme.cardShadow,
      ),
      child: child,
    );

    final Widget panel;
    if (kIsWeb) {
      panel = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: container,
        ),
      );
    } else {
      panel = container;
    }

    if (onTap != null) {
      return Semantics(
        button: true,
        label: semanticLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(borderRadius),
            child: panel,
          ),
        ),
      );
    }
    return semanticLabel != null
        ? Semantics(label: semanticLabel, child: panel)
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
    final sigma = 10.0;

    final content = Container(
      decoration: BoxDecoration(
        color: kIsWeb ? AppTheme.glassSurfaceContent : AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.glassBorderContent, width: 1),
        boxShadow: kIsWeb ? null : AppTheme.cardShadow,
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
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
