// lib/services/enregistrement_jeton.dart
//
// Jeton FCM de cet appareil enregistré sur le serveur (notifications push :
// sonneries de course, messages). Le serveur remplace le jeton s'il existe
// déjà (update_or_create) : réenregistrer est sans risque, une petite requête.
// - réponse vérifiée : 200 enregistré ; 426 : l'écran « Mise à jour requise »
//   s'ouvre (VersionApp) et on s'arrête ; 400, 401, 403, 404 : arrêt, inutile
//   d'insister ;
// - réseau, délai dépassé, 429, 5xx : nouvel essai, délais croissants, cinq
//   essais au plus ;
// - un seul envoi à la fois : un jeton plus récent arrivé pendant l'envoi est
//   envoyé ensuite (le plus récent gagne).
// Fichier identique dans taama_app et taama_conducteur.

import 'package:flutter/foundation.dart';

import 'api_service.dart';

enum IssueJeton { enregistre, miseAJourRequise, refuse, abandonne }

class EnregistrementJeton {
  EnregistrementJeton._();

  /// Délais avant chaque nouvel essai, croissants : cinq essais au plus.
  static const List<Duration> delaisParDefaut = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];

  @visibleForTesting
  static List<Duration> delais = delaisParDefaut;

  /// Issue du dernier enregistrement (tests, diagnostic).
  @visibleForTesting
  static IssueJeton? derniereIssue;

  static bool _enCours = false;
  static String? _plusRecent;

  /// Enregistre [jeton] (rien sans session ouverte ni jeton).
  static Future<void> enregistrer(String? jeton) async {
    if (jeton == null || jeton.isEmpty || !ApiService.estConnecte) return;
    if (_enCours) {
      _plusRecent = jeton; // envoyé à la fin de l'envoi en cours
      return;
    }
    _enCours = true;
    try {
      String? suivant = jeton;
      while (suivant != null) {
        derniereIssue = await _envoyer(suivant);
        final plusRecent = _plusRecent;
        _plusRecent = null;
        suivant = plusRecent == suivant ? null : plusRecent;
      }
    } finally {
      _enCours = false;
    }
  }

  static Future<IssueJeton> _envoyer(String jeton) async {
    for (var essai = 0;; essai++) {
      int? code;
      try {
        code = await ApiService.enregistrerTokenNotification(jeton);
      } catch (_) {
        code = null; // réseau, délai dépassé : on réessaiera
      }
      if (code == 200) return IssueJeton.enregistre;
      if (code == 426) return IssueJeton.miseAJourRequise;
      if (code != null && code != 429 && code < 500) return IssueJeton.refuse;
      if (essai >= delais.length) {
        if (kDebugMode) debugPrint('[Jeton] Enregistrement abandonné après ${essai + 1} essais');
        return IssueJeton.abandonne;
      }
      await Future<void>.delayed(delais[essai]);
      if (!ApiService.estConnecte) return IssueJeton.refuse; // déconnecté entre-temps
    }
  }

  @visibleForTesting
  static void reinitialiser() {
    delais = delaisParDefaut;
    derniereIssue = null;
    _enCours = false;
    _plusRecent = null;
  }
}
