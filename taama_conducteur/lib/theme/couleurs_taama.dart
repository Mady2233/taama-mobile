import 'package:flutter/material.dart';

/// Palette officielle de Taama, inspirée de l'artisanat malien (terre cuite
/// de Djenné, indigo bogolan). Centraliser les couleurs ici permet de les
/// ajuster partout d'un seul coup si besoin plus tard.
class CouleursTaama {
  static const Color indigo = Color(0xFF1C2B4A); // Couleur principale (remplace le noir)
  static const Color terreCuite = Color(0xFFC8623D); // Accent principal (remplace l'amber)
  static const Color sable = Color(0xFFF6EFE3); // Fond clair
  static const Color or = Color(0xFFD4A24C); // Accent secondaire (succès, highlights)

  static const Color grisTexte = Color(0xFF6B7280);
  static const Color blanc = Colors.white;

  // Ombres (accueil carte) : encre bleu nuit à 16 % et 8 %.
  static const Color ombre = Color(0x29101828);
  static const Color ombreLegere = Color(0x14101828);

  // Navigation de nuit (maquette « Conducteur »).
  static const Color nuitPanneau = Color(0xFF22273D);
  static const Color nuitTexteSecondaire = Color(0xFF9AA3C0);
  static const Color itineraireNuit = Color(0xFFF0997B);
}