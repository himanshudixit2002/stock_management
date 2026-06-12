import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../utils/responsive.dart';
import 'animations.dart';
import 'app_bar_title_row.dart';
import 'glass_panel.dart';
import 'shimmer_loading.dart';

/// Standardized scaffold for list and form screens.
///
/// Provides the shared gradient background, an [AppBarTitleRow] header with an
/// optional subtitle, a responsive max-width constraint for web/desktop, and an
/// optional [ShimmerLoading] placeholder while [isLoading] is true. Dark mode is
/// handled automatically via the [AppTheme] context helpers.
class AppScreenScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;

  /// When true, renders a [ShimmerLoading] placeholder instead of [body].
  final bool isLoading;
  final ShimmerLayout shimmerLayout;

  /// When true (default), the body is centered and constrained to a responsive
  /// max width. Set to false for bodies that manage their own width.
  final bool constrainWidth;

  /// Optional hero header zone rendered in a [GlassPanel] just below the app
  /// bar (e.g. a summary banner or key stats). Spans the constrained width.
  final Widget? header;

  /// When true (and not loading), [emptyState] is rendered instead of [body].
  /// Lets screens surface a consistent empty/error slot without restructuring.
  final bool isEmpty;
  final Widget? emptyState;

  /// When true (default), a subtle drifting gradient background is used (falls
  /// back to a static gradient under reduce-motion). Set false for a flat
  /// [AppTheme.scaffoldGrad] background.
  final bool animatedBackground;

  final Widget body;

  const AppScreenScaffold({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.isLoading = false,
    this.shimmerLayout = ShimmerLayout.card,
    this.constrainWidth = true,
    this.header,
    this.isEmpty = false,
    this.emptyState,
    this.animatedBackground = true,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppTheme.primaryColor;

    final Widget titleWidget = subtitle == null
        ? AppBarTitleRow(icon: icon, color: color, title: title)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.textPri(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: AppTheme.textSec(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );

    final Widget content;
    if (isLoading) {
      content = ShimmerLoading(layout: shimmerLayout);
    } else if (isEmpty && emptyState != null) {
      content = FadeSlideIn(child: emptyState!);
    } else {
      content = FadeSlideIn(child: body);
    }

    Widget inner = content;
    if (header != null) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: ScaleFadeIn(
              child: GlassPanel(
                padding: const EdgeInsets.all(16),
                useContentVariant: true,
                child: header!,
              ),
            ),
          ),
          Expanded(child: content),
        ],
      );
    }

    if (constrainWidth) {
      inner = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: inner,
        ),
      );
    }

    final Widget? fab = floatingActionButton == null
        ? null
        : ScaleFadeIn(child: floatingActionButton!);

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: leading,
        title: titleWidget,
        actions: actions,
      ),
      floatingActionButton: fab,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(child: inner),
    );

    if (animatedBackground) {
      // AnimatedGradientBackground renders a static gradient under reduce-motion.
      return AnimatedGradientBackground(
        colors: AppTheme.scaffoldGrad(context).colors,
        child: scaffold,
      );
    }

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: scaffold,
    );
  }
}
