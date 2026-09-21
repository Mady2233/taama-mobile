// lib/utils/format.dart
//
// Utilitaires de présentation partagés. Volontairement hors de
// taama_theme.dart : le thème décrit des tokens visuels, pas de la logique.

import 'package:flutter/material.dart';

/// « 12 500 F » — espace fine insécable, sans dépendance intl.
String formaterFcfa(int montant) {
  final negatif = montant < 0;
  final chiffres = montant.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    final restant = chiffres.length - i;
    buffer.write(chiffres[i]);
    if (restant > 1 && restant % 3 == 1) buffer.write(' ');
  }
  return '${negatif ? '-' : ''}$buffer F';
}

/// « 4,9 » — virgule décimale française.
String formaterNote(double note) =>
    note.toStringAsFixed(1).replaceAll('.', ',');

/// « 1,2 km » ou « 800 m ».
String formaterDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Traduit la couleur en texte libre du backend (« Blanche », « gris
/// métallisé »…) en pastille affichable.
///
/// Retourne null si la couleur n'est pas reconnue : l'écran n'affiche
/// alors aucune pastille plutôt qu'une couleur fausse, qui ferait
/// chercher la mauvaise voiture au client.
Color? couleurVehicule(String? libelle) {
  if (libelle == null) return null;

  final n = _normaliser(libelle);
  if (n.isEmpty) return null;

  const table = <String, Color>{
    'blanc': Colors.white,
    'noir': Color(0xFF1A1A1A),
    'gris': Color(0xFF9E9E9E),
    'argent': Color(0xFFC8CCD0),
    'rouge': Color(0xFFD32F2F),
    'bleu': Color(0xFF1976D2),
    'vert': Color(0xFF388E3C),
    'jaune': Color(0xFFFBC02D),
    'orange': Color(0xFFF57C00),
    'marron': Color(0xFF6D4C41),
    'beige': Color(0xFFE8D9B5),
    'dore': Color(0xFFCBA135),
    'violet': Color(0xFF7B1FA2),
    'rose': Color(0xFFEC407A),
  };

  // « grise », « blanche », « gris métallisé » → on cherche la racine.
  for (final entree in table.entries) {
    if (n.contains(entree.key)) return entree.value;
  }
  return null;
}

String _normaliser(String texte) {
  const accents = 'àâäáãçèéêëîïíìôöóòõùûüúñ';
  const sans = 'aaaaacceeeeiiiiooooouuuun';
  var t = texte.toLowerCase().trim();
  for (var i = 0; i < accents.length; i++) {
    t = t.replaceAll(accents[i], sans[i]);
  }
  return t;
}
