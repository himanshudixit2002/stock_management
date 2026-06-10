import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  /// Currency symbol used across the app.
  static const String currencySymbol = '₹';

  // Ocean teal — clean, professional, inventory-friendly
  static const Color primaryColor = Color(0xFF0D9488); // teal 600
  static const Color primaryLight = Color(0xFF2DD4BF); // teal 400
  static const Color primaryDark = Color(0xFF0F766E); // teal 700
  static const Color accentColor = Color(0xFF0284C7); // sky 600
  static const Color successColor = Color(0xFF16A34A);
  static const Color warningColor = Color(0xFFD97706);
  static const Color dangerColor = Color(0xFFDC2626);
  static const Color backgroundColor = Color(0xFFF8FAFC); // neutral slate 50
  static const Color surfaceColor = Colors.white;
  static const Color textPrimary = Color(0xFF1E293B); // slate 800
  static const Color textSecondary = Color(0xFF475569); // slate 600
  static const Color textTertiary = Color(0xFF64748B); // slate 500
  static const Color textMuted = Color(0xFF94A3B8); // slate 400
  static const Color iconMuted = Color(0xFF94A3B8);
  static const Color emptyStateIcon = Color(0xFFCBD5E1);
  static const Color dividerColor = Color(0xFFE8ECF0);
  static const Color dividerStrong = Color(0xFFD1D9E0);

  // Section accent extras (use sparingly)
  static const Color violetColor = Color(0xFF6366F1);
  static const Color pinkColor = Color(0xFFEC4899);
  static const Color cyanColor = Color(0xFF06B6D4);

  // Stock level colors
  static const Color stockGood = Color(0xFF16A34A);
  static const Color stockLow = Color(0xFFD97706);
  static const Color stockOut = Color(0xFFDC2626);

  static const Color infoColor = Color(0xFF0284C7);
  static const Color indigoColor = Color(0xFF6366F1);

  /// Foreground color for text/icons drawn on top of the brand gradient
  /// (heroGradient / primaryGradient). Stays white across both themes so
  /// contrast on the dark teal gradient is preserved.
  static const Color onGradient = Color(0xFFFFFFFF);

  /// Muted variant of [onGradient] for secondary text on the gradient.
  static const Color onGradientMuted = Color(0xE6FFFFFF);

  // Spacing constants
  static const double spacingXS = 4;
  static const double spacingSM = 8;
  static const double spacingMD = 12;
  static const double spacingLG = 16;
  static const double spacingXL = 24;
  static const double spacingXXL = 32;

  // Input field colors
  static const Color inputFillColor = Color(0xFFF1F5F9); // slate 100
  static const Color inputBorderColor = Color(0xFFE2E8F0); // slate 200

  // Dark-mode counterpart constants
  static const Color _darkBg = Color(0xFF121212);
  static const Color _darkSurface = Color(0xFF1E1E1E);
  static const Color _darkCard = Color(0xFF252525);
  static const Color _darkText = Color(0xFFE0E0E0);
  static const Color _darkTextSec = Color(0xFFBDBDBD);
  static const Color _darkTextTer = Color(0xFF9E9E9E);
  static const Color _darkDivider = Color(0xFF333333);
  static const Color _darkInputFill = Color(0xFF2A2A2A);

  // Context-aware color getters (automatically pick light/dark)
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color bg(BuildContext context) =>
      isDark(context) ? _darkBg : backgroundColor;

  static Color surface(BuildContext context) =>
      isDark(context) ? _darkSurface : surfaceColor;

  static Color card(BuildContext context) =>
      isDark(context) ? _darkCard : Colors.white;

  static Color textPri(BuildContext context) =>
      isDark(context) ? _darkText : textPrimary;

  static Color textSec(BuildContext context) =>
      isDark(context) ? _darkTextSec : textSecondary;

  static Color textTer(BuildContext context) =>
      isDark(context) ? _darkTextTer : textTertiary;

  static Color dividerC(BuildContext context) =>
      isDark(context) ? _darkDivider : dividerColor;

  static Color inputFill(BuildContext context) =>
      isDark(context) ? _darkInputFill : inputFillColor;

  static Color inputBorder(BuildContext context) =>
      isDark(context) ? const Color(0xFF444444) : inputBorderColor;

  static Color dividerStrongC(BuildContext context) =>
      isDark(context) ? const Color(0xFF3A3A3A) : dividerStrong;

  static Color emptyIcon(BuildContext context) =>
      isDark(context) ? const Color(0xFF888888) : emptyStateIcon;

  static Color iconMute(BuildContext context) =>
      isDark(context) ? const Color(0xFF888888) : iconMuted;

  static Color textMute(BuildContext context) =>
      isDark(context) ? const Color(0xFF888888) : textMuted;

  static LinearGradient scaffoldGrad(BuildContext context) => isDark(context)
      ? const LinearGradient(
          colors: [Color(0xFF121818), Color(0xFF161A1A), Color(0xFF1A1E1E)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        )
      : scaffoldGradient;

  // Glass tokens that adapt to dark mode
  static Color glassSurface(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.white.withValues(alpha: 0.25);

  static Color glassBorder(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.1)
      : Colors.white.withValues(alpha: 0.4);

  static Color glassContent(BuildContext context) => isDark(context)
      ? const Color(0xFF2A2A2A).withValues(alpha: 0.95)
      : Colors.white.withValues(alpha: 0.82);

  static Color glassBorderCont(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.15)
      : Colors.white.withValues(alpha: 0.7);

  // Liquid glass tokens
  static Color get glassSurfaceLight => Colors.white.withValues(alpha: 0.25);
  static Color get glassBorderLight => Colors.white.withValues(alpha: 0.4);
  static Color get glassOverlay => Colors.white.withValues(alpha: 0.08);
  static const double glassBlurSigma = 12;

  // Content-safe glass (higher opacity for text readability - WCAG)
  static Color get glassSurfaceContent => Colors.white.withValues(alpha: 0.82);
  static Color get glassBorderContent => Colors.white.withValues(alpha: 0.7);
  static Color get glassInputBackground => Colors.white.withValues(alpha: 0.35);
  static Color get glassOverlaySubtle => Colors.white.withValues(alpha: 0.12);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF0D9488), Color(0xFF0891B2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF15803D), Color(0xFF16A34A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFB91C1C), Color(0xFFDC2626)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient indigoGradient = LinearGradient(
    colors: [Color(0xFF0D9488), Color(0xFF2DD4BF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warmGradient = LinearGradient(
    colors: [Color(0xFFEA580C), Color(0xFFF97316)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFD97706), Color(0xFFFBBF24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF0F766E), Color(0xFF0D9488), Color(0xFF0891B2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient scaffoldGradient = LinearGradient(
    colors: [Color(0xFFFAFBFC), Color(0xFFF4F6F8), Color(0xFFFFFFFF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Shadow helpers (neutral, no color tint)
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get softShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.07),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> coloredShadow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.28),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  // Decoration helpers (rounded corners 16px)
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: cardShadow,
  );

  static BoxDecoration cardDeco(BuildContext context) => BoxDecoration(
    color: card(context),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: dividerC(context)),
  );

  static BoxDecoration get elevatedCardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    boxShadow: softShadow,
  );

  static BoxDecoration elevatedCardDeco(BuildContext context) => BoxDecoration(
    color: card(context),
    borderRadius: BorderRadius.circular(16),
    boxShadow: isDark(context) ? [] : softShadow,
    border: isDark(context) ? Border.all(color: dividerC(context)) : null,
  );

  static BoxDecoration glassDecoration({
    double borderRadius = 16,
    Border? border,
  }) => BoxDecoration(
    color: glassOverlay,
    borderRadius: BorderRadius.circular(borderRadius),
    border: border ?? Border.all(color: glassBorderLight, width: 1),
  );

  static BoxDecoration glassDeco(
    BuildContext context, {
    double borderRadius = 16,
    Border? border,
  }) => BoxDecoration(
    color: isDark(context)
        ? Colors.white.withValues(alpha: 0.04)
        : glassOverlay,
    borderRadius: BorderRadius.circular(borderRadius),
    border: border ?? Border.all(color: glassBorder(context), width: 1),
  );

  static BoxDecoration glassContentDecoration({
    double borderRadius = 16,
    Border? border,
  }) => BoxDecoration(
    color: glassSurfaceContent,
    borderRadius: BorderRadius.circular(borderRadius),
    border: border ?? Border.all(color: glassBorderContent, width: 1),
  );

  static BoxDecoration glassContentDeco(
    BuildContext context, {
    double borderRadius = 16,
    Border? border,
  }) => BoxDecoration(
    color: glassContent(context),
    borderRadius: BorderRadius.circular(borderRadius),
    border: border ?? Border.all(color: glassBorderCont(context), width: 1),
  );

  static Color getStockColor(int quantity, {int threshold = 10}) {
    if (quantity <= 0) return stockOut;
    if (quantity <= threshold) return stockLow;
    return stockGood;
  }

  static String getStockLabel(int quantity, {int threshold = 10}) {
    if (quantity <= 0) return 'Out of Stock';
    if (quantity <= threshold) return 'Low Stock';
    return 'In Stock';
  }

  static IconData getStockIcon(int quantity, {int threshold = 10}) {
    if (quantity <= 0) return Icons.error_rounded;
    if (quantity <= threshold) return Icons.warning_amber_rounded;
    return Icons.check_circle_rounded;
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
        primary: primaryColor,
        secondary: accentColor,
        surface: surfaceColor,
        error: dangerColor,
      ),
      scaffoldBackgroundColor: backgroundColor,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: textPrimary, size: 22),
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: textPrimary, height: 1.5),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: textTertiary,
          height: 1.4,
          letterSpacing: -0.2,
        ),
        bodySmall: TextStyle(fontSize: 12, color: textTertiary),
        labelLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),

      materialTapTargetSize: MaterialTapTargetSize.padded,

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          side: const BorderSide(color: primaryColor, width: 1.5),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: inputBorderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: dangerColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: dangerColor, width: 2),
        ),
        labelStyle: const TextStyle(fontSize: 15, color: textTertiary),
        hintStyle: const TextStyle(fontSize: 14, color: textMuted),
        prefixIconColor: textTertiary,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: textTertiary,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        selectedIconTheme: IconThemeData(size: 26),
        unselectedIconTheme: IconThemeData(size: 22),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF0F4F8),
        selectedColor: primaryColor,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: textTertiary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: dividerStrong, width: 1),
      ),

      dividerTheme: const DividerThemeData(
        color: dividerColor,
        thickness: 1,
        space: 1,
      ),

      scrollbarTheme: const ScrollbarThemeData(
        thumbVisibility: WidgetStatePropertyAll(false),
        trackVisibility: WidgetStatePropertyAll(false),
        thickness: WidgetStatePropertyAll(0),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData get darkTheme {
    const darkBg = Color(0xFF121212);
    const darkSurface = Color(0xFF1E1E1E);
    const darkCard = Color(0xFF252525);
    const darkText = Color(0xFFE0E0E0);
    const darkTextSecondary = Color(0xFF9E9E9E);
    const darkDivider = Color(0xFF333333);
    const darkInputFill = Color(0xFF2A2A2A);
    const darkInputBorder = Color(0xFF3A3A3A);
    const darkHintText = Color(0xFFB0B0B0);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
        primary: primaryLight,
        secondary: accentColor,
        surface: darkSurface,
        error: dangerColor,
      ),
      scaffoldBackgroundColor: darkBg,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkText,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: darkText,
          letterSpacing: -0.3,
        ),
        iconTheme: const IconThemeData(color: darkText, size: 22),
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: darkText,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: darkText,
          letterSpacing: -0.3,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: darkText,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: darkText, height: 1.5),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: darkTextSecondary,
          height: 1.4,
          letterSpacing: -0.2,
        ),
        bodySmall: TextStyle(fontSize: 12, color: darkTextSecondary),
        labelLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),

      materialTapTargetSize: MaterialTapTargetSize.padded,

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryLight,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryLight,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          side: const BorderSide(color: primaryLight, width: 1.5),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkInputBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: dangerColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: dangerColor, width: 2),
        ),
        labelStyle: const TextStyle(fontSize: 15, color: darkTextSecondary),
        hintStyle: const TextStyle(fontSize: 14, color: darkHintText),
        prefixIconColor: darkTextSecondary,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: darkCard,
        surfaceTintColor: Colors.transparent,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryLight,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: primaryLight,
        unselectedItemColor: darkTextSecondary,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        selectedIconTheme: IconThemeData(size: 26),
        unselectedIconTheme: IconThemeData(size: 22),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: darkCard,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: darkText,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: darkCard,
        selectedColor: primaryLight.withValues(alpha: 0.28),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: darkText,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: darkTextSecondary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: const BorderSide(color: darkDivider, width: 1),
      ),

      dividerTheme: const DividerThemeData(
        color: darkDivider,
        thickness: 1,
        space: 1,
      ),

      scrollbarTheme: const ScrollbarThemeData(
        thumbVisibility: WidgetStatePropertyAll(false),
        trackVisibility: WidgetStatePropertyAll(false),
        thickness: WidgetStatePropertyAll(0),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
