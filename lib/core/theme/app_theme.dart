import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

abstract final class AppTheme {
  static TextTheme _buildTextTheme(Color primaryText, Color secondaryText) {
    return TextTheme(
      displayLarge: AppTypography.displayLarge.copyWith(color: primaryText),
      displayMedium: AppTypography.displayMedium.copyWith(color: primaryText),
      headlineLarge: AppTypography.headlineLarge.copyWith(color: primaryText),
      headlineMedium: AppTypography.headlineMedium.copyWith(color: primaryText),
      headlineSmall: AppTypography.headlineSmall.copyWith(color: primaryText),
      titleLarge: AppTypography.titleLarge.copyWith(color: primaryText),
      titleMedium: AppTypography.titleMedium.copyWith(color: primaryText),
      bodyLarge: AppTypography.bodyLarge.copyWith(color: primaryText),
      bodyMedium: AppTypography.bodyMedium.copyWith(color: secondaryText),
      bodySmall: AppTypography.bodySmall.copyWith(color: secondaryText),
      labelLarge: AppTypography.labelLarge.copyWith(color: primaryText),
      labelMedium: AppTypography.labelMedium.copyWith(color: secondaryText),
    );
  }

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          secondary: AppColors.accent,
          onSecondary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          surfaceContainerHighest: AppColors.surfaceVariant,
          onSurfaceVariant: AppColors.textSecondary,
          outline: AppColors.borderLight,
          error: AppColors.error,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'Nunito',
        textTheme: _buildTextTheme(AppColors.textPrimary, AppColors.textSecondary),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
          titleTextStyle:
              AppTypography.headlineMedium.copyWith(color: AppColors.textPrimary),
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFD6CBEB),
            disabledForegroundColor: AppColors.textSecondary,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
            elevation: 2,
            shadowColor: AppColors.primary.withValues(alpha: 0.35),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFD6CBEB),
            disabledForegroundColor: AppColors.textSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.textHint,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            textStyle: AppTypography.labelLarge,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.textHint,
            textStyle: AppTypography.labelLarge,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF9F6FE),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.borderLight, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.borderLight, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primary, width: 2.0),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.error, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
          labelStyle: const TextStyle(
            color: Color(0xFF4A3E6B),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: const TextStyle(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          prefixIconColor: AppColors.primary,
          suffixIconColor: AppColors.textSecondary,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.12)),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfaceVariant,
          selectedColor: AppColors.primary,
          secondarySelectedColor: AppColors.primary,
          disabledColor: const Color(0xFFE9E2F6),
          labelStyle: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
          secondaryLabelStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
          checkmarkColor: Colors.white,
          side: const BorderSide(color: AppColors.borderLight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          titleTextStyle:
              AppTypography.headlineSmall.copyWith(color: AppColors.textPrimary),
          contentTextStyle:
              AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.surface,
          modalBackgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
        ),
        dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
          ),
          textStyle: const TextStyle(color: AppColors.textPrimary),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: AppColors.surface,
          textStyle: TextStyle(color: AppColors.textPrimary),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: AppColors.textPrimary,
          iconColor: AppColors.textSecondary,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return AppColors.textSecondary;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return const Color(0xFFDCD3EE);
          }),
        ),
        checkboxTheme: CheckboxThemeData(
          side: const BorderSide(color: AppColors.primary, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          checkColor: const WidgetStatePropertyAll(Colors.white),
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return const Color(0xFFFAF7FF);
          }),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textHint,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.borderLight),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryLight,
          onPrimary: Color(0xFF1A0D33),
          secondary: AppColors.accentLight,
          onSecondary: Color(0xFF2D0A1B),
          surface: AppColors.darkSurface,
          onSurface: AppColors.darkTextPrimary,
          surfaceContainerHighest: AppColors.darkSurfaceVariant,
          onSurfaceVariant: AppColors.darkTextSecondary,
          outline: AppColors.darkBorder,
          error: Color(0xFFFF6B63),
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: AppColors.darkBackground,
        fontFamily: 'Nunito',
        textTheme:
            _buildTextTheme(AppColors.darkTextPrimary, AppColors.darkTextSecondary),
        iconTheme: const IconThemeData(color: AppColors.darkTextPrimary),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.darkTextPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
          titleTextStyle: AppTypography.headlineMedium
              .copyWith(color: AppColors.darkTextPrimary),
          iconTheme: const IconThemeData(color: AppColors.darkTextPrimary),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF332357),
            disabledForegroundColor: AppColors.darkTextHint,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
            elevation: 2,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF332357),
            disabledForegroundColor: AppColors.darkTextHint,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryLight,
            disabledForegroundColor: AppColors.darkTextHint,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            side: const BorderSide(color: AppColors.primaryLight, width: 1.5),
            textStyle: AppTypography.labelLarge,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryLight,
            disabledForegroundColor: AppColors.darkTextHint,
            textStyle: AppTypography.labelLarge,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkInputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.darkBorder, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.darkBorder, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: AppColors.primaryLight, width: 2.0),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFFF6B63), width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          hintStyle: const TextStyle(color: AppColors.darkTextHint, fontSize: 14),
          labelStyle: const TextStyle(
            color: AppColors.darkTextSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: const TextStyle(
            color: AppColors.primaryLight,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          prefixIconColor: AppColors.primaryLight,
          suffixIconColor: AppColors.darkTextSecondary,
        ),
        cardTheme: CardThemeData(
          color: AppColors.darkSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.darkBorder),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.darkSurfaceVariant,
          selectedColor: AppColors.primary,
          secondarySelectedColor: AppColors.primary,
          disabledColor: const Color(0xFF2B1E47),
          labelStyle: const TextStyle(
            color: AppColors.darkTextPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
          secondaryLabelStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
          checkmarkColor: Colors.white,
          side: const BorderSide(color: AppColors.darkBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.darkSurface,
          titleTextStyle: AppTypography.headlineSmall
              .copyWith(color: AppColors.darkTextPrimary),
          contentTextStyle: AppTypography.bodyMedium
              .copyWith(color: AppColors.darkTextSecondary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.darkSurface,
          modalBackgroundColor: AppColors.darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.primaryLight,
          unselectedLabelColor: AppColors.darkTextSecondary,
          indicatorColor: AppColors.primaryLight,
        ),
        dropdownMenuTheme: DropdownMenuThemeData(
          menuStyle: MenuStyle(
            backgroundColor:
                const WidgetStatePropertyAll(AppColors.darkSurface),
          ),
          textStyle: const TextStyle(color: AppColors.darkTextPrimary),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: AppColors.darkSurface,
          textStyle: TextStyle(color: AppColors.darkTextPrimary),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: AppColors.darkTextPrimary,
          iconColor: AppColors.darkTextSecondary,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return AppColors.darkTextSecondary;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return AppColors.darkSurfaceVariant;
          }),
        ),
        checkboxTheme: CheckboxThemeData(
          side: const BorderSide(color: AppColors.primaryLight, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          checkColor: const WidgetStatePropertyAll(Colors.white),
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.darkInputFill;
          }),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkSurface,
          selectedItemColor: AppColors.primaryLight,
          unselectedItemColor: AppColors.darkTextHint,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.darkSurfaceVariant,
          contentTextStyle: const TextStyle(color: AppColors.darkTextPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.darkBorder),
      );
}
