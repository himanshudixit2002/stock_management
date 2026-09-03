import 'package:flutter/material.dart';

class AppTheme {
  /// Fallback currency symbol only. The company's configured symbol lives in
  /// [BillingSettingsProvider]; read it through `Money` (lib/utils/currency.dart)
  /// so a company that switched currency sees it on every screen, not just
  /// billing documents.
  static const String currencySymbol = '₹';

  // ---------------------------------------------------------------------------
  // Palette — indigo on zinc
  //
  // Every semantic colour is a LIGHT/DARK PAIR. The previous palette used one
  // hex on both grounds, which left danger and warning contrast-marginal on a
  // near-black background. Read them through the context helpers below
  // (`danger(context)`, not `dangerColor`) anywhere the theme can be dark.
  //
  // The bare constants are kept because ~2,900 call sites reference them and
  // they are still correct in light mode and on gradients; they now carry the
  // light value of each pair.
  // ---------------------------------------------------------------------------

  static const Color primaryColor = Color(0xFF0D9488); // teal 600
  static const Color primaryLight = Color(0xFF2DD4BF); // teal 400
  static const Color primaryDark = Color(0xFF0F766E); // teal 700
  static const Color accentColor = Color(0xFF0891B2); // cyan 600
  static const Color successColor = Color(0xFF16A34A);
  static const Color warningColor = Color(0xFFD97706);
  static const Color dangerColor = Color(0xFFDC2626);
  static const Color infoColor = Color(0xFF2563EB);

  // Dark counterparts — lifted so they read against #09090B.
  static const Color _primaryDarkMode = Color(0xFF2DD4BF);
  static const Color _accentDarkMode = Color(0xFF22D3EE);
  static const Color _successDarkMode = Color(0xFF4ADE80);
  static const Color _warningDarkMode = Color(0xFFFBBF24);
  static const Color _dangerDarkMode = Color(0xFFF87171);
  static const Color _infoDarkMode = Color(0xFF60A5FA);

  /// Tinted fill behind an icon or chip in the brand colour.
  static const Color primaryTintLight = Color(0xFFF0FDFA); // teal 50

  // Neutrals — zinc rather than slate: neutral enough to sit under indigo
  // without the blue cast slate carries, and it gives a true near-black dark
  // mode instead of the old #121212 grey.
  static const Color backgroundColor = Color(0xFFFAFAFA); // zinc 50
  static const Color surfaceColor = Colors.white;
  static const Color textPrimary = Color(0xFF18181B); // zinc 900
  static const Color textSecondary = Color(0xFF52525B); // zinc 600
  static const Color textTertiary = Color(0xFF71717A); // zinc 500
  static const Color textMuted = Color(0xFFA1A1AA); // zinc 400
  static const Color iconMuted = Color(0xFFA1A1AA);
  static const Color emptyStateIcon = Color(0xFFD4D4D8); // zinc 300
  static const Color dividerColor = Color(0xFFE4E4E7); // zinc 200
  static const Color dividerStrong = Color(0xFFD4D4D8); // zinc 300

  // Section accent extras (use sparingly)
  static const Color violetColor = Color(0xFF6366F1);
  static const Color pinkColor = Color(0xFFEC4899);
  static const Color cyanColor = Color(0xFF06B6D4);
  static const Color indigoColor = Color(0xFF6366F1);

  // Stock level colors
  static const Color stockGood = Color(0xFF16A34A);
  static const Color stockLow = Color(0xFFD97706);
  static const Color stockOut = Color(0xFFDC2626);

  /// A categorical ramp for charts and category chips.
  ///
  /// Lives here rather than inside a chart widget: the pie chart used to carry
  /// six raw hex values of its own that belonged to no palette and had no dark
  /// variant. Ordered so adjacent slices stay distinguishable.
  static const List<Color> chartRampLight = [
    Color(0xFF0D9488), Color(0xFF0891B2), Color(0xFF16A34A), Color(0xFFD97706),
    Color(0xFF6366F1), Color(0xFFEC4899), Color(0xFF0EA5E9), Color(0xFF65A30D),
    Color(0xFFDC2626), Color(0xFF7C3AED), Color(0xFFF59E0B), Color(0xFF64748B),
  ];

  static const List<Color> chartRampDark = [
    Color(0xFF2DD4BF), Color(0xFF22D3EE), Color(0xFF4ADE80), Color(0xFFFBBF24),
    Color(0xFF818CF8), Color(0xFFF472B6), Color(0xFF38BDF8), Color(0xFFA3E635),
    Color(0xFFF87171), Color(0xFFA78BFA), Color(0xFFFCD34D), Color(0xFF94A3B8),
  ];

  static List<Color> chartRamp(BuildContext context) =>
      isDark(context) ? chartRampDark : chartRampLight;

  /// Foreground color for text/icons drawn on top of the brand gradient.
  /// Stays white across both themes.
  static const Color onGradient = Color(0xFFFFFFFF);

  /// Muted variant of [onGradient] for secondary text on the gradient.
  static const Color onGradientMuted = Color(0xE6FFFFFF);

  /// Foreground for text/icons drawn on a [warningColor] fill.
  ///
  /// Near-black in both themes, because the amber itself does not change with
  /// the theme — white on it fails contrast either way. Named rather than
  /// written as a literal so the pairing is stated once.
  static Color onWarning(BuildContext context) => const Color(0xDD000000);

  // Spacing scale.
  static const double spacingXS = 4;
  static const double spacingSM = 8;
  static const double spacingMD = 12;
  static const double spacingLG = 16;
  static const double spacingXL = 24;
  static const double spacingXXL = 32;

  /// Corner radius scale.
  ///
  /// Previously every call site picked its own value — 16 for cards, 18 for
  /// buttons, 20 for dialogs, 28 for the nav pill — with no relationship
  /// between them.
  static const double radiusXS = 6;
  static const double radiusSM = 10;
  static const double radiusMD = 14;
  static const double radiusLG = 18;
  static const double radiusXL = 24;
  static const double radiusPill = 999;

  // Input field colors
  static const Color inputFillColor = Color(0xFFF4F4F5); // zinc 100
  static const Color inputBorderColor = Color(0xFFE4E4E7); // zinc 200

  // Dark-mode neutrals — zinc 950/900/800.
  static const Color _darkBg = Color(0xFF101214);
  static const Color _darkSurface = Color(0xFF181B1E);
  static const Color _darkCard = Color(0xFF212529);
  static const Color _darkText = Color(0xFFFAFAFA);
  static const Color _darkTextSec = Color(0xFFD4D4D8);
  static const Color _darkTextTer = Color(0xFFA1A1AA);
  static const Color _darkMuted = Color(0xFF71717A);
  static const Color _darkDivider = Color(0xFF262A2E);
  static const Color _darkDividerStrong = Color(0xFF383D42);
  static const Color _darkInputFill = Color(0xFF181B1E);

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
      isDark(context) ? _darkDividerStrong : inputBorderColor;

  static Color dividerStrongC(BuildContext context) =>
      isDark(context) ? _darkDividerStrong : dividerStrong;

  static Color emptyIcon(BuildContext context) =>
      isDark(context) ? _darkDividerStrong : emptyStateIcon;

  static Color iconMute(BuildContext context) =>
      isDark(context) ? _darkMuted : iconMuted;

  static Color textMute(BuildContext context) =>
      isDark(context) ? _darkMuted : textMuted;

  static Color onPrimary(BuildContext context) => Colors.white;

  // Semantic colours, theme-aware.
  //
  // Prefer these over the bare constants anywhere the surface can be dark: the
  // light values are too dark to read on a near-black ground.
  static Color primary(BuildContext context) =>
      isDark(context) ? _primaryDarkMode : primaryColor;

  static Color accent(BuildContext context) =>
      isDark(context) ? _accentDarkMode : accentColor;

  static Color success(BuildContext context) =>
      isDark(context) ? _successDarkMode : successColor;

  static Color warning(BuildContext context) =>
      isDark(context) ? _warningDarkMode : warningColor;

  static Color danger(BuildContext context) =>
      isDark(context) ? _dangerDarkMode : dangerColor;

  static Color info(BuildContext context) =>
      isDark(context) ? _infoDarkMode : infoColor;

  /// A low-alpha fill of [color] for icon chips and tinted rows.
  ///
  /// Dark mode needs more alpha to register against the surface, so the value
  /// is not a single constant.
  static Color tint(BuildContext context, Color color) =>
      color.withValues(alpha: isDark(context) ? 0.18 : 0.12);

  static Color primaryTint(BuildContext context) =>
      isDark(context) ? _primaryDarkMode.withValues(alpha: 0.18) : primaryTintLight;

  /// Elevation as a shadow in light mode and as nothing in dark.
  ///
  /// On a #09090B ground a drop shadow is invisible, which is why call sites
  /// were all writing `isDark(context) ? [] : AppTheme.cardShadow` by hand.
  /// Depth in dark mode comes from the tonal step between bg/surface/card plus
  /// the border instead.
  static List<BoxShadow> shadowFor(BuildContext context, {int level = 1}) {
    if (isDark(context)) return const [];
    return switch (level) {
      0 => const [],
      1 => cardShadow,
      2 => softShadow,
      _ => const [
        BoxShadow(color: Color(0x14000000), blurRadius: 32, offset: Offset(0, 12)),
        BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4)),
      ],
    };
  }

  static LinearGradient scaffoldGrad(BuildContext context) => isDark(context)
      ? const LinearGradient(
          colors: [Color(0xFF101214), Color(0xFF141719), Color(0xFF181B1E)],
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
      ? _darkCard
      : Colors.white;

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

  // Gradients.
  //
  // The bare constants carry the light-mode values. Prefer the `*Grad(context)`
  // helpers below on any surface that can be dark — the light gradients are far
  // too heavy against a near-black ground.
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
    colors: [Color(0xFFFAFAFA), Color(0xFFF6F6F7), Color(0xFFFFFFFF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Dark counterparts, dimmer and lower-contrast so a gradient panel reads as a
  // surface rather than a light source.
  static const LinearGradient _primaryGradientDark = LinearGradient(
    colors: [Color(0xFF115E59), Color(0xFF155E75)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient _heroGradientDark = LinearGradient(
    colors: [Color(0xFF134E4A), Color(0xFF115E59), Color(0xFF155E75)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient _successGradientDark = LinearGradient(
    colors: [Color(0xFF14532D), Color(0xFF166534)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient _dangerGradientDark = LinearGradient(
    colors: [Color(0xFF7F1D1D), Color(0xFF991B1B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient _warningGradientDark = LinearGradient(
    colors: [Color(0xFF78350F), Color(0xFF92400E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient primaryGrad(BuildContext context) =>
      isDark(context) ? _primaryGradientDark : primaryGradient;

  static LinearGradient heroGrad(BuildContext context) =>
      isDark(context) ? _heroGradientDark : heroGradient;

  static LinearGradient successGrad(BuildContext context) =>
      isDark(context) ? _successGradientDark : successGradient;

  static LinearGradient dangerGrad(BuildContext context) =>
      isDark(context) ? _dangerGradientDark : dangerGradient;

  static LinearGradient warningGrad(BuildContext context) =>
      isDark(context) ? _warningGradientDark : warningGradient;

  // Shadow helpers (neutral, no color tint)
  static List<BoxShadow> get cardShadow => const [
    BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
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

  /// Built once and reused.
  ///
  /// This was a getter, so every rebuild of the `Consumer<ThemeProvider>` that
  /// wraps `MaterialApp` constructed a brand-new [ThemeData] — including a
  /// `ColorScheme.fromSeed`, which runs the Material 3 HCT algorithm to derive
  /// thirteen tonal palettes. Both themes were rebuilt each time, on the
  /// startup path, for a value that never changes.
  /// The full type scale, in Inter.
  ///
  /// Every slot is defined on purpose. Six were previously left null
  /// (`displayLarge/Medium/Small`, `titleSmall`, `labelMedium/Small`) and fell
  /// back to the Material 3 baseline, which ignores these colours — so a
  /// `titleSmall` anywhere in the app rendered in the framework's default ink
  /// rather than the app's.
  ///
  /// Tracking is tuned for Inter specifically: it needs negative letter-spacing
  /// as sizes grow and slightly positive spacing at caption sizes to stay
  /// legible.
  static TextTheme _textTheme({
    required Color ink,
    required Color sec,
    required Color ter,
  }) => TextTheme(
    displayLarge: TextStyle(
      fontSize: 44, fontWeight: FontWeight.w700, color: ink, letterSpacing: -1.2, height: 1.1),
    displayMedium: TextStyle(
      fontSize: 36, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.9, height: 1.15),
    displaySmall: TextStyle(
      fontSize: 30, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.7, height: 1.2),
    headlineLarge: TextStyle(
      fontSize: 26, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.6, height: 1.25),
    headlineMedium: TextStyle(
      fontSize: 22, fontWeight: FontWeight.w700, color: ink, letterSpacing: -0.4, height: 1.3),
    headlineSmall: TextStyle(
      fontSize: 19, fontWeight: FontWeight.w600, color: ink, letterSpacing: -0.3, height: 1.3),
    titleLarge: TextStyle(
      fontSize: 17, fontWeight: FontWeight.w600, color: ink, letterSpacing: -0.2),
    titleMedium: TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, color: ink, letterSpacing: -0.1),
    titleSmall: TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600, color: sec),
    bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.5),
    bodyMedium: TextStyle(
      fontSize: 14, color: ter, height: 1.45, letterSpacing: -0.1),
    bodySmall: TextStyle(fontSize: 12, color: ter, height: 1.4),
    labelLarge: TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, color: ink, letterSpacing: 0.1),
    labelMedium: TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, color: sec, letterSpacing: 0.2),
    labelSmall: TextStyle(
      fontSize: 11, fontWeight: FontWeight.w600, color: ter, letterSpacing: 0.4),
  );

  static final ThemeData lightTheme = _buildLightTheme();

  static ThemeData _buildLightTheme() {
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

      fontFamily: 'Inter',
      textTheme: _textTheme(
        ink: textPrimary,
        sec: textSecondary,
        ter: textTertiary,
      ),


      // ---- Components that previously fell back to raw Material ----
      //
      // TextButton in particular is every dialog's Cancel action, and it was
      // rendering in the framework default rather than the app's ink.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSM),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMD),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSM),
          ),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(radiusXS),
        ),
        textStyle: const TextStyle(
          color: Color(0xFFFAFAFA),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXL)),
        ),
        // No global drag handle: SlideUpSheet draws its own, and enabling this
        // gave those sheets two.
      ),

      listTileTheme: ListTileThemeData(
        iconColor: textTertiary,
        textColor: textPrimary,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.1,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: textTertiary, height: 1.35),
        // Deliberately no `shape` or `minVerticalPadding`: several screens set
        // `dense`/`visualDensity` on their own tiles, and a global geometry
        // override fights them and changes row heights app-wide.
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryColor
              : dividerColor,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryColor
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(
          Colors.white,
        ),
        side: BorderSide(color: dividerColor, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryColor
              : textTertiary,
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: primaryColor,
        unselectedLabelColor: textTertiary,
        indicatorColor: primaryColor,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primaryColor,
        linearTrackColor: dividerColor,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: primaryColor.withValues(alpha: 0.14),
          selectedForegroundColor: primaryColor,
          foregroundColor: textTertiary,
          side: BorderSide(color: dividerColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSM),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMD),
          side: BorderSide(color: dividerColor),
        ),
        textStyle: TextStyle(fontSize: 14, color: textPrimary),
      ),

      expansionTileTheme: ExpansionTileThemeData(
        iconColor: primaryColor,
        collapsedIconColor: textTertiary,
        textColor: textPrimary,
        collapsedTextColor: textPrimary,
        shape: const Border(),
        collapsedShape: const Border(),
      ),

      badgeTheme: BadgeThemeData(
        backgroundColor: dangerColor,
        textColor: Colors.white,
        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceColor,
        indicatorColor: primaryColor.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(color: primaryColor, size: 24),
        unselectedIconTheme: IconThemeData(color: textTertiary, size: 24),
        selectedLabelTextStyle: TextStyle(
          color: primaryColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: textTertiary, fontSize: 12),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: dividerColor,
        thumbColor: primaryColor,
        overlayColor: primaryColor.withValues(alpha: 0.12),
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

  /// Built once and reused — see [lightTheme].
  static final ThemeData darkTheme = _buildDarkTheme();

  static ThemeData _buildDarkTheme() {
    // Aliases of the class-level tokens rather than a second set of values.
    // These were previously independent literals on the old grey palette, so
    // the ThemeData and the AppTheme.*(context) helpers disagreed about what
    // "dark surface" meant.
    const darkBg = _darkBg;
    const darkSurface = _darkSurface;
    const darkCard = _darkCard;
    const darkText = _darkText;
    const darkTextSec = _darkTextSec;
    const darkTextTer = _darkTextTer;
    const darkTextSecondary = _darkTextTer;
    const darkDivider = _darkDivider;
    const darkInputFill = _darkInputFill;
    const darkInputBorder = _darkDividerStrong;
    const darkHintText = _darkTextTer;

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

      fontFamily: 'Inter',
      textTheme: _textTheme(
        ink: _darkText,
        sec: _darkTextSec,
        ter: _darkTextTer,
      ),


      // ---- Components that previously fell back to raw Material ----
      //
      // TextButton in particular is every dialog's Cancel action, and it was
      // rendering in the framework default rather than the app's ink.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryLight,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSM),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryLight,
          foregroundColor: const Color(0xFF101214),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMD),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: darkTextSec,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSM),
          ),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF3F3F46),
          borderRadius: BorderRadius.circular(radiusXS),
        ),
        textStyle: const TextStyle(
          color: Color(0xFFFAFAFA),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: darkSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXL)),
        ),
        // See the light theme — SlideUpSheet draws its own handle.
      ),

      listTileTheme: ListTileThemeData(
        iconColor: darkTextTer,
        textColor: darkText,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: darkText,
          letterSpacing: -0.1,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: darkTextTer, height: 1.35),
        // Deliberately no `shape` or `minVerticalPadding`: several screens set
        // `dense`/`visualDensity` on their own tiles, and a global geometry
        // override fights them and changes row heights app-wide.
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : darkTextTer,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryLight
              : darkDivider,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryLight
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(
          const Color(0xFF101214),
        ),
        side: BorderSide(color: darkDivider, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(5),
        ),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryLight
              : darkTextTer,
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: primaryLight,
        unselectedLabelColor: darkTextTer,
        indicatorColor: primaryLight,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primaryLight,
        linearTrackColor: darkDivider,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: primaryLight.withValues(alpha: 0.14),
          selectedForegroundColor: primaryLight,
          foregroundColor: darkTextTer,
          side: BorderSide(color: darkDivider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSM),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: darkCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMD),
          side: BorderSide(color: darkDivider),
        ),
        textStyle: TextStyle(fontSize: 14, color: darkText),
      ),

      expansionTileTheme: ExpansionTileThemeData(
        iconColor: primaryLight,
        collapsedIconColor: darkTextTer,
        textColor: darkText,
        collapsedTextColor: darkText,
        shape: const Border(),
        collapsedShape: const Border(),
      ),

      badgeTheme: BadgeThemeData(
        backgroundColor: const Color(0xFFF87171),
        textColor: const Color(0xFF101214),
        textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: darkSurface,
        indicatorColor: primaryLight.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(color: primaryLight, size: 24),
        unselectedIconTheme: IconThemeData(color: darkTextTer, size: 24),
        selectedLabelTextStyle: TextStyle(
          color: primaryLight,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: darkTextTer, fontSize: 12),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: primaryLight,
        inactiveTrackColor: darkDivider,
        thumbColor: primaryLight,
        overlayColor: primaryLight.withValues(alpha: 0.12),
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
