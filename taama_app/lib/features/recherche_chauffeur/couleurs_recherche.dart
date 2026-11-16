import 'package:flutter/material.dart';

import '../../theme/taama_theme.dart';
import 'chauffeur_proche.dart';

/// Palette de l'écran : les couleurs du thème Taama, plus celles que le thème
/// n'a pas (badge moto, alerte, bouton désactivé, gris du panneau, avatars).
abstract final class CouleursRecherche {
  static const nuit = TaamaColors.night;
  static const indigo = TaamaColors.primary;
  static const indigoPale = TaamaColors.primarySoft;
  static const indigoDesactive = Color(0xFFC7C2F7);
  static const ambre = Color(0xFFF6B92B);
  static const direct = TaamaColors.accentMint;
  static const alerte = Color(0xFFF59E0B);
  static const texte = TaamaColors.textPrimary;
  static const texteDoux = TaamaColors.textSecondary;
  static const bordure = TaamaColors.border;
  static const panneau = TaamaColors.surface;
  static const poignee = Color(0xFFD9DBE5);
  static const gris = Color(0xFFF0F1F6);
  static const grisClair = Color(0xFFF6F7FA);
  static const ombrePanneau = Color(0x40000000);

  static const _avatars = <Color>[
    Color(0xFF0F7A64),
    Color(0xFF4B3FD1),
    Color(0xFFB45309),
    Color(0xFF15803D),
    Color(0xFFA3174A),
    Color(0xFF1D4ED8),
    Color(0xFF7C3AED),
    Color(0xFF0E7490),
  ];

  /// Couleur d'avatar stable pour un même chauffeur.
  static Color avatar(String id) {
    var empreinte = 0;
    for (final unite in id.codeUnits) {
      empreinte = (empreinte * 31 + unite) & 0x7fffffff;
    }
    return _avatars[empreinte % _avatars.length];
  }

  static Color vehicule(TypeVehicule type) =>
      vehiculeEstMoto(type == TypeVehicule.moto);

  /// La même couleur sans le modèle du radar : la carte d'accueil
  /// (ConducteurProche) n'a qu'un booléen.
  static Color vehiculeEstMoto(bool estMoto) => estMoto ? ambre : indigo;
}
