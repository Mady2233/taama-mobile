import 'package:flutter/material.dart';

import '../donnees/carte_bamako.dart';

/// Couleurs de la couche carte (quartiers, repères, attribution). Fichier
/// identique dans taama_app et taama_conducteur : chaque app reste autonome.
/// Chaque pastille porte une icône blanche : toutes ces teintes sont assez
/// foncées pour un contraste suffisant, et se distinguent aussi en clarté.
class CouleursCarte {
  CouleursCarte._();

  // Étiquettes de quartier : texte + halo, jour et nuit.
  static const Color quartierJour = Color(0xFF4B5263);
  static const Color sousQuartierJour = Color(0xFF6B7385);
  static const Color haloJour = Color(0xFFFFFFFF);
  static const Color quartierNuit = Color(0xFFB4BBD4);
  static const Color sousQuartierNuit = Color(0xFF8A93B2);
  static const Color haloNuit = Color(0xFF181C2E);

  // Nom d'un repère.
  static const Color repereJour = Color(0xFF2F3545);
  static const Color repereNuit = Color(0xFFD6DAE8);

  // Attribution (fond translucide pour rester lisible sur la carte).
  static const Color attributionTexteJour = Color(0xFF344054);
  static const Color attributionFondJour = Color(0xD9FFFFFF);
  static const Color attributionTexteNuit = Color(0xFFD0D5E2);
  static const Color attributionFondNuit = Color(0xCC181C2E);

  static const Color iconeRepere = Color(0xFFFFFFFF);

  // Fond affiché à la place des tuiles quand la carte n'est pas configurée.
  static const Color fondIndisponibleJour = Color(0xFFEEF0F4);
  static const Color fondIndisponibleNuit = Color(0xFF181C2E);

  static const Map<CategorieRepere, Color> pastille = {
    CategorieRepere.marche: Color(0xFFC2410C),
    CategorieRepere.hopital: Color(0xFFB42318),
    CategorieRepere.gare: Color(0xFF175CD3),
    CategorieRepere.universite: Color(0xFF6941C6),
    CategorieRepere.centreCommercial: Color(0xFFA11043),
    CategorieRepere.pont: Color(0xFF475467),
    CategorieRepere.clinique: Color(0xFFD92D20),
    CategorieRepere.culte: Color(0xFF0F6E56),
    CategorieRepere.carburant: Color(0xFF93370D),
    CategorieRepere.banque: Color(0xFF344054),
    CategorieRepere.police: Color(0xFF1D2939),
    CategorieRepere.pharmacie: Color(0xFF067647),
  };
}
