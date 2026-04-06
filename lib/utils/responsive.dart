import 'package:flutter/material.dart';

enum ScreenType { mobile, tablet, desktop }

class Responsive {
  static const double mobileBreakpoint = 560;
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
        return 48;
    }
  }

  static double contentMaxWidth(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return double.infinity;
      case ScreenType.tablet:
        return 900;
      case ScreenType.desktop:
        return 1600;
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
        return 900;
    }
  }

  static int gridColumns(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return 1;
      case ScreenType.tablet:
        return 2;
      case ScreenType.desktop:
        return 4;
    }
  }

  /// Max width for bottom sheets and dialogs on wider screens.
  static double dialogMaxWidth(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return double.infinity;
      case ScreenType.tablet:
        return 480;
      case ScreenType.desktop:
        return 560;
    }
  }

  /// Grid columns for list screens (less aggressive than product grid).
  static int listGridColumns(BuildContext context) {
    switch (screenType(context)) {
      case ScreenType.mobile:
        return 1;
      case ScreenType.tablet:
        return 2;
      case ScreenType.desktop:
        return 3;
    }
  }

  /// Scales font size by the system text scaler (accessibility).
  /// Use for text that should respect user's font size preferences.
  static double fontSizeScaled(BuildContext context, double baseSize) {
    return MediaQuery.textScalerOf(context).scale(baseSize);
  }

  /// Minimum touch target size per Apple HIG (44 logical pixels).
  static const double minTouchTargetSize = 44;

  /// Padding to wrap small icon buttons to meet min touch target (44pt).
  static double minTouchTargetPadding(BuildContext context) {
    return (minTouchTargetSize - iconSize(context)) / 2;
  }

  /// Returns constraints for bottom sheets — null on mobile, max-width on wider screens.
  static BoxConstraints? sheetConstraints(BuildContext context) {
    if (isMobile(context)) return null;
    return BoxConstraints(maxWidth: dialogMaxWidth(context));
  }

  /// Android: ClampingScrollPhysics for native feel. Others: AlwaysScrollableScrollPhysics.
  static ScrollPhysics scrollPhysics(BuildContext context) {
    return Theme.of(context).platform == TargetPlatform.android
        ? const ClampingScrollPhysics()
        : const AlwaysScrollableScrollPhysics();
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
        child: padding != null
            ? Padding(padding: padding!, child: child)
            : child,
      ),
    );
  }
}

/// A bottom sheet wrapper that constrains width on tablet/desktop.
Future<T?> showResponsiveBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  Color? backgroundColor,
  double? maxHeightFactor,
}) {
  final isMobile = Responsive.isMobile(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor ?? Colors.transparent,
    constraints: isMobile
        ? null
        : BoxConstraints(maxWidth: Responsive.dialogMaxWidth(context)),
    builder: (sheetCtx) {
      final child = builder(sheetCtx);
      if (maxHeightFactor != null) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetCtx).height * maxHeightFactor,
          ),
          child: child,
        );
      }
      return child;
    },
  );
}

/// Lays children side-by-side on tablet/desktop, stacked on mobile.
/// Useful for form fields like Name + Email, Price + Quantity.
class ResponsiveFormRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const ResponsiveFormRow({
    super.key,
    required this.children,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (Responsive.isMobile(context) || children.length < 2) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i < children.length - 1) SizedBox(width: spacing),
        ],
      ],
    );
  }
}

/// Wraps body content in a centered ConstrainedBox with responsive padding.
/// Use as the body of a Scaffold for consistent layout across screens.
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final bool useFormWidth;

  const ResponsiveBody({
    super.key,
    required this.child,
    this.useFormWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final maxW = useFormWidth
        ? Responsive.formMaxWidth(context)
        : Responsive.contentMaxWidth(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: child,
      ),
    );
  }
}
