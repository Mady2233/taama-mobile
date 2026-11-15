import 'package:flutter/material.dart';

import 'chauffeur_proche.dart';

/// Palette de l'écran, relevée sur la maquette. À remplacer par les
/// constantes du thème Taama (bleu nuit + indigo) si elles existent déjà.
abstract final class CouleursRecherche {
  static const nuit = Color(0xFF151A3D);
  static const indigo = Color(0xFF5546E8);
  static const indigoPale = Color(0xFFEEECFF);
  static const indigoDesactive = Color(0xFFC7C2F7);
  static const ambre = Color(0xFFF6B92B);
  static const direct = Color(0xFF2DD4BF);
  static const alerte = Color(0xFFF59E0B);
  static const texte = Color(0xFF14172E);
  static const texteDoux = Color(0xFF6B7088);
  static const bordure = Color(0xFFE8E9F1);
  static const panneau = Color(0xFFFFFFFF);

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
      type == TypeVehicule.moto ? ambre : indigo;
}
