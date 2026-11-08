import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class ArenaTokens extends ThemeExtension<ArenaTokens> {
  const ArenaTokens({
    required this.ink,
    required this.secondary,
    required this.muted,
    required this.card,
    required this.raised,
    required this.line,
    required this.success,
    required this.warning,
  });
  final Color ink, secondary, muted, card, raised, line, success, warning;
  static const violet = Color(0xFF5B4CFF);
  static const amber = Color(0xFFF6BB45);
  static const navy = Color(0xFF1D2E61);
  static const blue = Color(0xFF354B9A);
  static const teal = Color(0xFF087F73);
  static const coral = Color(0xFFB95D3D);
  static const gold = Color(0xFFFFDF8A);
  static const silver = Color(0xFFDCE4EB);
  static const bronze = Color(0xFFF9C9B1);
  static const spacing = [4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 32.0, 40.0, 48.0];
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const ease = Cubic(.22, 1, .36, 1);
  @override
  ArenaTokens copyWith({
    Color? ink,
    Color? secondary,
    Color? muted,
    Color? card,
    Color? raised,
    Color? line,
    Color? success,
    Color? warning,
  }) => ArenaTokens(
    ink: ink ?? this.ink,
    secondary: secondary ?? this.secondary,
    muted: muted ?? this.muted,
    card: card ?? this.card,
    raised: raised ?? this.raised,
    line: line ?? this.line,
    success: success ?? this.success,
    warning: warning ?? this.warning,
  );
  @override
  ArenaTokens lerp(ArenaTokens? other, double t) => other == null
      ? this
      : ArenaTokens(
          ink: Color.lerp(ink, other.ink, t)!,
          secondary: Color.lerp(secondary, other.secondary, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          card: Color.lerp(card, other.card, t)!,
          raised: Color.lerp(raised, other.raised, t)!,
          line: Color.lerp(line, other.line, t)!,
          success: Color.lerp(success, other.success, t)!,
          warning: Color.lerp(warning, other.warning, t)!,
        );
}

extension ArenaTheme on BuildContext {
  ArenaTokens get tokens => Theme.of(this).extension<ArenaTokens>()!;
  TextTheme get type => Theme.of(this).textTheme;
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
}

ThemeData arenaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final tokens = ArenaTokens(
    ink: dark ? const Color(0xFFF0F4FC) : const Color(0xFF17233D),
    secondary: dark ? const Color(0xFFCAD5E9) : const Color(0xFF52617B),
    muted: dark ? const Color(0xFFA6B5CF) : const Color(0xFF64718A),
    card: dark ? const Color(0xFF18243B) : Colors.white,
    raised: dark ? const Color(0xFF23324C) : const Color(0xFFEDF1F8),
    line: dark ? const Color(0xFF354664) : const Color(0xFFE2E7F0),
    success: dark ? const Color(0xFF7BD5A1) : const Color(0xFF237348),
    warning: dark ? const Color(0xFFE9C17D) : const Color(0xFF8A5A18),
  );
  final background = dark ? const Color(0xFF10192B) : const Color(0xFFF5F7FB);
  final primary = dark ? const Color(0xFFB3C5FF) : ArenaTokens.blue;
  final colors =
      ColorScheme.fromSeed(
        seedColor: ArenaTokens.violet,
        brightness: brightness,
      ).copyWith(
        primary: primary,
        onPrimary: dark ? const Color(0xFF162347) : Colors.white,
        secondary: tokens.secondary,
        onSecondary: tokens.card,
        secondaryContainer: tokens.raised,
        onSecondaryContainer: tokens.ink,
        surface: tokens.card,
        onSurface: tokens.ink,
        onSurfaceVariant: tokens.secondary,
        surfaceContainerLowest: tokens.card,
        surfaceContainerLow: tokens.raised,
        surfaceContainer: tokens.raised,
        surfaceContainerHigh: tokens.raised,
        surfaceContainerHighest: tokens.line,
        outline: tokens.muted,
        outlineVariant: tokens.line,
      );
  TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.4,
    String family = 'Poppins',
    Color? color,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: 0,
    color: color ?? tokens.ink,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Poppins',
    colorScheme: colors,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    iconTheme: IconThemeData(size: 20, color: tokens.secondary),
    visualDensity: VisualDensity.standard,
  );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  return base.copyWith(
    extensions: [tokens],
    textTheme: base.textTheme
        .apply(
          fontFamily: 'Poppins',
          bodyColor: tokens.ink,
          displayColor: tokens.ink,
        )
        .copyWith(
          headlineLarge: text(
            32,
            weight: FontWeight.w600,
            height: 1.2,
            family: 'Poppins',
          ),
          headlineMedium: text(
            28,
            weight: FontWeight.w600,
            height: 1.25,
            family: 'Poppins',
          ),
          headlineSmall: text(
            24,
            weight: FontWeight.w600,
            height: 1.3,
            family: 'Poppins',
          ),
          titleLarge: text(20, weight: FontWeight.w600, height: 1.35),
          titleMedium: text(16, weight: FontWeight.w600),
          titleSmall: text(14, weight: FontWeight.w600),
          bodyLarge: text(16, height: 1.5),
          bodyMedium: text(14, height: 1.5),
          bodySmall: text(12, height: 1.5, color: tokens.muted),
          labelLarge: text(14, weight: FontWeight.w600),
          labelMedium: text(12, weight: FontWeight.w600),
          labelSmall: text(12),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: ArenaTokens.navy,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      toolbarHeight: 68,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: text(18, weight: FontWeight.w600, color: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white, size: 22),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: colors.onPrimary,
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: text(15, weight: FontWeight.w600),
        shape: buttonShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.ink,
        side: BorderSide(color: tokens.line),
        minimumSize: const Size(48, 52),
        textStyle: text(15, weight: FontWeight.w600),
        shape: buttonShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(48, 48),
        textStyle: text(14, weight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.card,
      contentPadding: const EdgeInsets.all(16),
      labelStyle: text(14, color: tokens.secondary),
      hintStyle: text(14, color: tokens.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: tokens.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: tokens.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    dividerTheme: DividerThemeData(color: tokens.line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.secondary,
      titleTextStyle: text(15, weight: FontWeight.w600),
      subtitleTextStyle: text(13, color: tokens.secondary),
      minLeadingWidth: 24,
      horizontalTitleGap: 12,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: tokens.card,
      selectedColor: tokens.raised,
      side: BorderSide(color: tokens.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: text(13),
      secondaryLabelStyle: text(13, weight: FontWeight.w600),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: tokens.line,
      circularTrackColor: tokens.line,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 70,
      indicatorColor: primary,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? colors.onPrimary
              : tokens.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text(
          12,
          weight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? tokens.ink
              : tokens.muted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: tokens.card,
      indicatorColor: primary.withValues(alpha: .1),
      selectedIconTheme: IconThemeData(size: 20, color: primary),
      unselectedIconTheme: IconThemeData(size: 20, color: tokens.muted),
      selectedLabelTextStyle: text(14, weight: FontWeight.w600),
      unselectedLabelTextStyle: text(14, color: tokens.secondary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: tokens.ink,
      contentTextStyle: text(14, color: tokens.card),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
