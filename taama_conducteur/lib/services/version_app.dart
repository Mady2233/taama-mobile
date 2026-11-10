// lib/services/version_app.dart
//
// Version de l'app annoncée au serveur à chaque requête (en-tête X-Taama-App,
// « client/android/64 ») et réponse 426 « Mise à jour requise » du serveur
// (trajets/versions_apps.py) : l'écran bloquant s'affiche (MiseAJour). Fichier
// identique dans taama_app et taama_conducteur.

import 'dart:convert';

import 'package:flutter/foundation.dart';

class VersionApp {
  VersionApp._();

  static String? _enTete;

  /// « app/plateforme/build », ou null tant que le build n'est pas lu.
  static String? get enTete => _enTete;

  static void annoncer({required String app, required String plateforme, required int build}) {
    _enTete = '$app/$plateforme/$build';
  }

  @visibleForTesting
  static void oublier() => _enTete = null;

  /// À ajouter aux en-têtes de chaque requête (rien tant que le build est
  /// inconnu : le serveur laisse alors toujours passer).
  static Map<String, String> entetes() => _enTete == null ? const {} : {'X-Taama-App': _enTete!};

  /// Branché par MiseAJour : affiche l'écran bloquant, avec la fiche du store
  /// envoyée par le serveur s'il y en a une.
  static void Function(String? lien)? surMiseAJourRequise;

  /// Nombre de réponses « Mise à jour requise » reçues. Le serveur ne les
  /// envoie jamais pendant une course : MiseAJour s'en sert pour savoir s'il
  /// y en a une.
  static int refusRecus = 0;

  /// Vrai si la réponse est un « Mise à jour requise » du serveur ; prévient
  /// alors l'app. Appelé par ApiService avant de lire une erreur.
  static bool signaler(int statut, String corps) {
    if (statut != 426) return false;
    try {
      final donnees = jsonDecode(corps);
      if (donnees is! Map || donnees['code'] != 'MISE_A_JOUR_REQUISE') return false;
      refusRecus++;
      final lien = donnees['lien'];
      surMiseAJourRequise?.call(lien is String && lien.startsWith('https://') ? lien : null);
      return true;
    } catch (_) {
      return false;
    }
  }
}
