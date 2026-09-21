// lib/theme/taama_theme.dart
//
// Système de design de l'app client Taama (v3 — maquette validée).
// Bleu nuit dominant, indigo comme accent unique, ambre réservé au Confort
// et aux alertes. Aucune valeur hex ne doit apparaître dans les écrans.

import 'package:flutter/material.dart';

class TaamaColors {
  TaamaColors._();

  // Marque
  static const Color navy = Color(0xFF2A1D6E); // en-têtes, bandeaux forts
  static const Color navyLight = Color(0xFF3A2A8F); // puces sur navy
  static const Color primary = Color(0xFF4A38C9); // accent unique
  static const Color primarySoft = Color(0xFFEFEDFD);
  static const Color onNavyMuted = Color(0xFFA79FEA); // texte secondaire /navy

  // Fonds et surfaces
  static const Color background = Color(0xFFF4F5FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1F3F7);
  static const Color mapPlaceholder = Color(0xFFE9EDF2);
  static const Color border = Color(0xFFE4E7EE);

  // Écran de suivi (thème nuit)
  static const Color night = Color(0xFF181C2E); // feuille
  static const Color nightRaised = Color(0xFF22273D); // blocs internes
  static const Color nightControl = Color(0xFF2E3450); // boutons secondaires
  static const Color nightBorder = Color(0xFF3A4160);
  static const Color onNightMuted = Color(0xFF9AA3C0);
  static const Color onNightFaint = Color(0xFF6E7899);
  static const Color mapNight = Color(0xFF22273D);
  static const Color routeNight = Color(0xFF8B7BFF);
  static const Color routeHaloNight = Color(0x406C5CE7);
  static const Color routeHaloDay = Color(0xFFFFFFFF);
  static const Color accentMint = Color(0xFF5DCAA5); // statut en direct
  static const Color dangerNight = Color(0xFFF0997B);
  static const Color dangerNightBg = Color(0xFF4A1B0C);

  // Texte
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF5F6B7A);
  static const Color textOnDark = Color(0xFFFFFFFF);

  // Sémantique
  static const Color success = Color(0xFF0F6E56);
  static const Color successSoft = Color(0xFFE1F5EE);
  static const Color warning = Color(0xFF854F0B); // texte sur ambre
  static const Color warningSoft = Color(0xFFFBF0DC);
  static const Color star = Color(0xFFBA7517);
  static const Color danger = Color(0xFFA32D2D);
  static const Color dangerSoft = Color(0xFFFCEBEB);
}

class TaamaRadius {
  TaamaRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

class TaamaSpacing {
  TaamaSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 18;
  static const double xl = 24;
}

class TaamaShadows {
  TaamaShadows._();
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F101828), blurRadius: 14, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x1F101828), blurRadius: 20, offset: Offset(0, 8)),
  ];
}

class TaamaTheme {
  TaamaTheme._();

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: TaamaColors.primary,
      onPrimary: TaamaColors.textOnDark,
      secondary: TaamaColors.navy,
      onSecondary: TaamaColors.textOnDark,
      error: TaamaColors.danger,
      onError: TaamaColors.textOnDark,
      surface: TaamaColors.surface,
      onSurface: TaamaColors.textPrimary,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: TaamaColors.background,
      textTheme: base.textTheme.apply(
        bodyColor: TaamaColors.textPrimary,
        displayColor: TaamaColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TaamaColors.navy,
        foregroundColor: TaamaColors.textOnDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      // Largeur minimale finie : Size.fromHeight(x) = Size(infini, x) rend
      // tout bouton placé dans un Row (ou toute largeur non bornée) illisible
      // ("BoxConstraints forces an infinite width") et vide l'écran. Un
      // bouton pleine largeur s'enveloppe explicitement dans
      // SizedBox(width: double.infinity).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TaamaColors.primary,
          foregroundColor: TaamaColors.textOnDark,
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TaamaRadius.lg),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TaamaColors.textPrimary,
          side: const BorderSide(color: TaamaColors.border),
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TaamaRadius.lg),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TaamaColors.surface,
        hintStyle: const TextStyle(color: TaamaColors.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TaamaRadius.lg),
          borderSide: const BorderSide(color: TaamaColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TaamaRadius.lg),
          borderSide: const BorderSide(color: TaamaColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TaamaRadius.lg),
          borderSide: const BorderSide(color: TaamaColors.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: TaamaColors.surface,
        indicatorColor: TaamaColors.primarySoft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? TaamaColors.primary : TaamaColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? TaamaColors.primary : TaamaColors.textSecondary,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: TaamaColors.border,
        thickness: 0.5,
        space: 0.5,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: TaamaColors.navy,
        contentTextStyle: const TextStyle(color: TaamaColors.textOnDark),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TaamaRadius.md),
        ),
      ),
    );
  }
}
