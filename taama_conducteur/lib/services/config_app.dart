// État d'affichage lu sur le serveur (GET /api/config-app/) : aujourd'hui,
// seulement « le paiement dans l'app est-il actif ? ». Fichier identique dans
// taama_app et taama_conducteur.
//
// Fail-closed : tant que le serveur n'a JAMAIS confirmé paiement_actif=true,
// portefeuille, solde, recharge et « Payer » restent masqués. Serveur
// injoignable : on garde la dernière valeur confirmée (le serveur refuse de
// toute façon un paiement en mode gratuit), gratuite par défaut.

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

  static const String _cle = 'config_app_paiement_actif';

  /// Au démarrage, AVANT runApp : la dernière valeur confirmée, sans réseau
  /// (aucun délai d'ouverture).
  static Future<void> chargerValeurGardee({SharedPreferences? preferences}) async {
    try {
      final prefs = preferences ?? await SharedPreferences.getInstance();
      paiementActif.value = prefs.getBool(_cle) ?? false;
    } catch (_) {
      paiementActif.value = false;
    }
  }

  /// Interroge le serveur (sans attendre au démarrage : appelé sans await).
  /// Toute réponse inattendue ou erreur réseau laisse la valeur actuelle.
  static Future<void> rafraichir({http.Client? client, SharedPreferences? preferences}) async {
    final c = client ?? http.Client();
    try {
      final reponse = await c
          .get(Uri.parse('${ApiConfig.siteUrl}/api/config-app/'))
          .timeout(const Duration(seconds: 12));
      if (reponse.statusCode != 200) return;
      final donnees = jsonDecode(reponse.body);
      if (donnees is! Map || donnees['paiement_actif'] is! bool) return;
      final actif = donnees['paiement_actif'] as bool;
      paiementActif.value = actif;
      final prefs = preferences ?? await SharedPreferences.getInstance();
      await prefs.setBool(_cle, actif);
    } catch (_) {
      // Injoignable, délai dépassé, réponse illisible : rien ne change.
    } finally {
      if (client == null) c.close();
    }
  }
}
