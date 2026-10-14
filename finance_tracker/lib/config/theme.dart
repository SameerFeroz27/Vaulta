import 'package:flutter/material.dart';

/// App theme: an M3 reskin of the reviewed prototype — surface container tiers in place of
/// the flat greys, larger button and sheet radii — with blue still reserved for buttons and
/// interactive elements (clicks, proceed, FABs, selected states).
class AppTheme {
  AppTheme._();

  static const Color _primaryBlue = Color(0xFF1976D2);

  /// Surface container: the M3 tier cards sit on, replacing the old #F5F5F5 / #1E1E1E.
  /// The reviewed prototype's values, paired with the hairline edges below.
  static const Color _lightSurface = Color(0xFFEAEEF5);
  static const Color _darkSurface = Color(0xFF24282F);

  /// Hairline edge for every surface. A fill this close to the page has no edge of its own,
  /// so cards read as washed out without one.
  static const Color _lightOutline = Color(0xFFE2E6EE);
  static const Color _darkOutline = Color(0xFF333941);

  /// Themed scrollbar. A black thumb vanishes into the dark surface, so dark takes a
  /// mid-grey that clears it and light a grey that reads on white.
  static const Color _lightScrollThumb = Color(0xFFC4C7CC);
  static const Color _darkScrollThumb = Color(0xFF4D5157);

  /// The M3 reskin's button radius, replacing 8 px so the primary buttons read as M3.
  static const double _buttonRadius = 20;

  /// Sheet top radius, part of the reskin's sheet treatment alongside the drag handle.
  static const double _sheetRadius = 28;

  /// Semantic colors for financial data (not UI chrome). These are the values used on a
  /// dark surface — the same tints are too light for body text on a light one, so
  /// [incomeFor], [expenseFor] and [warnFor] return deeper shades in light mode.
  static const Color expenseColor = Color(0xFFE53935);
  static const Color incomeColor = Color(0xFF43A047);
  static const Color warnColor = Color(0xFFFFB74D);

  static const Color _incomeLight = Color(0xFF2E7D32);
  static const Color _expenseLight = Color(0xFFC62828);
  static const Color _warnLight = Color(0xFFB45309);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color incomeFor(BuildContext context) =>
      isDark(context) ? incomeColor : _incomeLight;

  static Color expenseFor(BuildContext context) =>
      isDark(context) ? expenseColor : _expenseLight;

  static Color warnFor(BuildContext context) =>
      isDark(context) ? warnColor : _warnLight;

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primaryBlue,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        primary: _primaryBlue,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      cardTheme: const CardThemeData(
        color: _lightSurface,
        elevation: 0,
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: _lightOutline),
        ),
      ),
      // The app bar registers a scroll: the tint appears under it as content passes, rather
      // than the elevation being pinned to 0 so nothing ever moves.
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        scrolledUnderElevation: 3,
        surfaceTintColor: colorScheme.surfaceTint,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primaryBlue,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: const BorderSide(color: _lightOutline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _primaryBlue),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
      // Sheets carry a 28 px top radius and a drag handle; every call site opens through
      // one shared helper so they cannot drift.
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_sheetRadius),
          ),
        ),
      ),
      // Loans sub-tabs are secondary: a filled pill marks the selection, not an underline.
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: _primaryBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        labelColor: _primaryBlue,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(6),
        radius: Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(_lightScrollThumb),
        trackColor: WidgetStatePropertyAll(Colors.white),
      ),
      chipTheme: ChipThemeData(
        selectedColor: _primaryBlue,
        backgroundColor: _lightSurface,
        labelStyle: const TextStyle(fontSize: 13),
        side: BorderSide.none,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE0E0E0),
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _primaryBlue,
      ),
    );
  }

  static ThemeData get dark {
    const darkScaffold = Color(0xFF121212);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primaryBlue,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        primary: _primaryBlue,
        surface: darkScaffold,
      ),
      scaffoldBackgroundColor: darkScaffold,
      cardTheme: const CardThemeData(
        color: _darkSurface,
        elevation: 0,
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: _darkOutline),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkScaffold,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 3,
        surfaceTintColor: colorScheme.surfaceTint,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primaryBlue,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: const BorderSide(color: _darkOutline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_buttonRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _primaryBlue),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primaryBlue,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_sheetRadius),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: _primaryBlue.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(999),
        ),
        labelColor: _primaryBlue,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(6),
        radius: Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(_darkScrollThumb),
        trackColor: WidgetStatePropertyAll(darkScaffold),
      ),
      chipTheme: ChipThemeData(
        selectedColor: _primaryBlue,
        backgroundColor: _darkSurface,
        labelStyle: const TextStyle(fontSize: 13),
        side: BorderSide.none,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF333333),
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _primaryBlue,
      ),
    );
  }
}
