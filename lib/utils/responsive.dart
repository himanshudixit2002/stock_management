import 'package:flutter/material.dart';

enum ScreenType { mobile, tablet, desktop }

class Responsive {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1024;

  static ScreenType screenType(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= tabletBreakpoint) return ScreenType.desktop;
    if (width >= mobileBreakpoint) return ScreenType.tablet;
    return ScreenType.mobile;
  }

  static bool isMobile(BuildContext context) =>
      screenType(context) == ScreenType.mobile;

  static bool isTablet(BuildContext context) =>
      screenType(context) == ScreenType.tablet;

  static bool isDesktop(BuildContext context) =>
      screenType(context) == ScreenType.desktop;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= mobileBreakpoint;

  static double horizontalPadding(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return 16;
      case ScreenType.tablet:
        return 24;
      case ScreenType.desktop:
        return 40;
    }
  }

  static double contentMaxWidth(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return double.infinity;
      case ScreenType.tablet:
        return 720;
      case ScreenType.desktop:
        return 1200;
    }
  }

  static double cardPadding(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return 14;
      case ScreenType.tablet:
        return 16;
      case ScreenType.desktop:
        return 18;
    }
  }

  static double chartHeight(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return 200;
      case ScreenType.tablet:
        return 240;
      case ScreenType.desktop:
        return 280;
    }
  }

  static double iconSize(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return 20;
      case ScreenType.tablet:
        return 22;
      case ScreenType.desktop:
        return 24;
    }
  }

  static EdgeInsets responsivePadding(BuildContext context) {
    final h = horizontalPadding(context);
    return EdgeInsets.symmetric(horizontal: h, vertical: h * 0.75);
  }

  static double formMaxWidth(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return double.infinity;
      case ScreenType.tablet:
        return 600;
      case ScreenType.desktop:
        return 720;
    }
  }

  static int gridColumns(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return 1;
      case ScreenType.tablet:
        return 2;
      case ScreenType.desktop:
        return 3;
    }
  }
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= Responsive.tabletBreakpoint) {
          return desktop ?? tablet ?? mobile;
        }
        if (constraints.maxWidth >= Responsive.mobileBreakpoint) {
          return tablet ?? mobile;
        }
        return mobile;
      },
    );
  }
}

class ResponsiveCenter extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const ResponsiveCenter({
    super.key,
    this.maxWidth = 600,
    this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}
