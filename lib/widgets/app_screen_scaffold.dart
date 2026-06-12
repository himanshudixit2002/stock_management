import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../utils/responsive.dart';
import 'app_bar_title_row.dart';
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

    Widget content = isLoading
        ? ShimmerLoading(layout: shimmerLayout)
        : body;

    if (constrainWidth) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.contentMaxWidth(context),
          ),
          child: content,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGrad(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: leading,
          title: titleWidget,
          actions: actions,
        ),
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
        body: SafeArea(child: content),
      ),
    );
  }
}
