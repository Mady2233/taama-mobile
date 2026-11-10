// État d'affichage lu sur le serveur (GET /api/config-app/) : « le paiement
// dans l'app est-il actif ? » et, par app et par plateforme, les versions
// minimale (en dessous : bloqué) et recommandée (en dessous : bandeau) — voir
// mise_a_jour.dart. Fichier identique dans taama_app et taama_conducteur.
//
// Fail-closed : tant que le serveur n'a JAMAIS confirmé paiement_actif=true,
// portefeuille, solde, recharge et « Payer » restent masqués. Serveur
// injoignable : on garde la dernière valeur confirmée (le serveur refuse de
// toute façon un paiement en mode gratuit), gratuite par défaut. Même règle
// pour les versions minimales : la dernière valeur confirmée est gardée.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class ConfigApp {
  ConfigApp._();

  /// Écouté par les écrans (ValueListenableBuilder) : bascule sans
  /// redémarrer l'app quand la réponse du serveur arrive.
  static final ValueNotifier<bool> paiementActif = ValueNotifier(false);

  /// Plus petit numéro de build encore accepté, par app (« client »,
  /// « chauffeur »), sur Android. Vide tant que le serveur n'a rien dit.
  /// Champ des serveurs d'avant `versions`, gardé en secours.
  static final ValueNotifier<Map<String, int>> versionsMin = ValueNotifier(const {});

  /// Versions par « app/plateforme » (ex. « client/android »). Vide tant que
  /// le serveur n'a rien dit.
  static final ValueNotifier<Map<String, VersionsCible>> versions = ValueNotifier(const {});

  static const String _cle = 'config_app_paiement_actif';
  static const String _cleVersions = 'config_app_versions_min';
  static const String _cleVersionsCibles = 'config_app_versions';

  /// Versions exigée et recommandée pour cette app sur cette plateforme. Sans
  /// réponse du serveur : la dernière valeur connue ; jamais connue : rien
  /// n'est exigé.
  static VersionsCible cible(String app, String plateforme) {
    final connue = versions.value['$app/$plateforme'];
    if (connue != null) return connue;
    final minimale = plateforme == 'android' ? versionsMin.value[app] ?? 0 : 0;
    return VersionsCible(minimale: minimale, recommandee: 0);
  }

  /// Rafraîchissement lancé au démarrage, attendu par l'écran de démarrage.
  static Future<void>? _rafraichissement;

  /// Au démarrage, AVANT runApp : la dernière valeur confirmée, sans réseau
  /// (aucun délai d'ouverture).
  static Future<void> chargerValeurGardee({SharedPreferences? preferences}) async {
    try {
      final prefs = preferences ?? await SharedPreferences.getInstance();
      paiementActif.value = prefs.getBool(_cle) ?? false;
      versionsMin.value = _lireVersions(prefs.getString(_cleVersions));
      versions.value = _lireCibles(prefs.getString(_cleVersionsCibles));
    } catch (_) {
      paiementActif.value = false;
      versionsMin.value = const {};
      versions.value = const {};
    }
  }

  /// Interroge le serveur (sans attendre au démarrage : appelé sans await).
  /// Toute réponse inattendue ou erreur réseau laisse la valeur actuelle.
  static Future<void> rafraichir({http.Client? client, SharedPreferences? preferences}) =>
      _rafraichissement = _rafraichir(client: client, preferences: preferences);

  /// Attend le rafraîchissement en cours, au plus [delai] : passé ce délai, la
  /// dernière valeur confirmée fait foi.
  static Future<void> attendreRafraichissement({Duration delai = const Duration(seconds: 4)}) async {
    final enCours = _rafraichissement;
    if (enCours == null) return;
    try {
      await enCours.timeout(delai);
    } catch (_) {
      // Délai dépassé : on décide avec ce qui est connu.
    }
  }

  static Future<void> _rafraichir({http.Client? client, SharedPreferences? preferences}) async {
    final c = client ?? http.Client();
    try {
      final reponse = await c
          .get(Uri.parse('${ApiConfig.siteUrl}/api/config-app/'))
          .timeout(const Duration(seconds: 12));
      if (reponse.statusCode != 200) return;
      final donnees = jsonDecode(reponse.body);
      if (donnees is! Map) return;
      final prefs = preferences ?? await SharedPreferences.getInstance();
      if (donnees['paiement_actif'] is bool) {
        final actif = donnees['paiement_actif'] as bool;
        paiementActif.value = actif;
        await prefs.setBool(_cle, actif);
      }
      if (donnees['version_min'] is Map) {
        final versions = _lireVersions(donnees['version_min']);
        versionsMin.value = versions;
        await prefs.setString(_cleVersions, jsonEncode(versions));
      }
      if (donnees['versions'] is Map) {
        final cibles = _lireCibles(donnees['versions']);
        versions.value = cibles;
        await prefs.setString(
          _cleVersionsCibles,
          jsonEncode({for (final e in cibles.entries) e.key: e.value.versJson()}),
        );
      }
    } catch (_) {
      // Injoignable, délai dépassé, réponse illisible : rien ne change.
    } finally {
      if (client == null) c.close();
    }
  }

  /// Forme du serveur ({app: {plateforme: {minimale, recommandee, lien}}}) ou
  /// forme gardée ({« app/plateforme » : {…}}). Entrée illisible : ignorée.
  static Map<String, VersionsCible> _lireCibles(Object? brut) {
    Object? donnees = brut;
    if (brut is String) {
      try {
        donnees = jsonDecode(brut);
      } catch (_) {
        return const {};
      }
    }
    if (donnees is! Map) return const {};
    final cibles = <String, VersionsCible>{};
    for (final entree in donnees.entries) {
      if (entree.key is! String) continue;
      final cle = entree.key as String;
      final valeur = entree.value;
      if (cle.contains('/')) {
        final cible = VersionsCible.depuisJson(valeur);
        if (cible != null) cibles[cle] = cible;
      } else if (valeur is Map) {
        for (final plateforme in valeur.entries) {
          final cible = VersionsCible.depuisJson(plateforme.value);
          if (plateforme.key is String && cible != null) cibles['$cle/${plateforme.key}'] = cible;
        }
      }
    }
    return cibles;
  }

  /// Seulement les numéros entiers positifs ; tout le reste est ignoré.
  static Map<String, int> _lireVersions(Object? brut) {
    Object? donnees = brut;
    if (brut is String) {
      try {
        donnees = jsonDecode(brut);
      } catch (_) {
        return const {};
      }
    }
    if (donnees is! Map) return const {};
    return {
      for (final entree in donnees.entries)
        if (entree.key is String && entree.value is int && (entree.value as int) >= 0)
          entree.key as String: entree.value as int,
    };
  }
}

/// Versions d'une app sur une plateforme (numéros de build). 0 : rien.
class VersionsCible {
  const VersionsCible({required this.minimale, required this.recommandee, this.lien});

  final int minimale;
  final int recommandee;

  /// Fiche du store (App Store pour iOS) ; null : la fiche Play Store.
  final String? lien;

  static VersionsCible? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final minimale = brut['minimale'];
    final recommandee = brut['recommandee'];
    if (minimale is! int || recommandee is! int || minimale < 0 || recommandee < 0) return null;
    final lien = brut['lien'];
    return VersionsCible(
      minimale: minimale,
      recommandee: recommandee,
      lien: lien is String && lien.startsWith('https://') ? lien : null,
    );
  }

  Map<String, Object?> versJson() => {'minimale': minimale, 'recommandee': recommandee, 'lien': lien};
}
