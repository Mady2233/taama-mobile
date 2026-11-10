// lib/services/mise_a_jour.dart
//
// Mise à jour de l'app. Le serveur fixe, pour cette app et cette plateforme
// (config-app, réglées dans l'admin APRÈS chaque publication) :
// - une version minimale : en dessous, l'app s'arrête sur « Mise à jour
//   requise » — au démarrage, au retour au premier plan, ou quand le serveur
//   répond 426 à une requête (VersionApp) ;
// - une version recommandée : en dessous, un bandeau qu'on peut fermer.
// Google Play qui propose une version plus récente : le bandeau seulement.
// Jamais de blocage pendant une course ou une livraison (c'est le serveur
// qui tranche, voir courseSelonServeur) ; configuration injoignable : la
// dernière valeur connue, sinon rien n'est exigé.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../screens/mise_a_jour_requise_page.dart';
import 'api_service.dart';
import 'config_app.dart';
import 'demande_entrante_navigator.dart' show navigatorKey;
import 'version_app.dart';

enum EtatMiseAJour { aJour, recommandee, requise }

/// Issue du bouton « Mettre à jour ».
enum IssueMiseAJour {
  /// Google Play installe la nouvelle version (l'app redémarre d'elle-même),
  /// ou la fiche du store s'est ouverte.
  lancee,

  /// L'utilisateur a fermé l'écran de Google Play.
  annulee,

  /// Ni la mise à jour intégrée ni la fiche du store n'ont pu s'ouvrir.
  impossible,
}

class MiseAJour {
  MiseAJour._();

  /// Clé de cette app dans la configuration du serveur.
  static const String cleApp = 'chauffeur';
  static const String _paquet = 'com.taama.taama_conducteur';

  static String get plateforme => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Où en est le build installé face aux versions du serveur. Build inconnu
  /// ou versions à 0 : à jour, jamais un blocage.
  static EtatMiseAJour etat({required int? installe, required VersionsCible cible}) {
    if (installe == null) return EtatMiseAJour.aJour;
    if (cible.minimale > 0 && installe < cible.minimale) return EtatMiseAJour.requise;
    if (cible.recommandee > 0 && installe < cible.recommandee) return EtatMiseAJour.recommandee;
    return EtatMiseAJour.aJour;
  }

  /// Build que le bandeau propose : la recommandée, la minimale (blocage
  /// reporté pendant une course) ou celle de Google Play, la plus haute ;
  /// null si rien n'est plus récent que le build installé.
  static int? cibleBandeau({required int? installe, required VersionsCible cible, int? versionPlay}) {
    if (installe == null) return null;
    final candidates = [cible.recommandee, cible.minimale, versionPlay ?? 0].where((v) => v > installe);
    return candidates.isEmpty ? null : candidates.reduce((a, b) => a > b ? a : b);
  }

  /// Une fiche où envoyer l'utilisateur : le Play Store sur Android ; sur iOS,
  /// seulement le lien réglé dans l'admin. Sans fiche, rien à installer :
  /// jamais de blocage.
  static bool ficheConnue(String? lien) => plateforme == 'android' || lien != null;

  static int? _build;

  /// Null si illisible ou trop lent (2 s) : jamais un démarrage bloqué.
  static Future<int?> buildInstalle() async {
    if (_build != null) return _build;
    try {
      final info = await PackageInfo.fromPlatform().timeout(const Duration(seconds: 2));
      return _build = int.tryParse(info.buildNumber);
    } catch (_) {
      return null;
    }
  }

  /// Au démarrage, avant les premières requêtes : la version est annoncée au
  /// serveur, et sa réponse 426 ouvre l'écran bloquant.
  static Future<void> annoncerVersion() async {
    final build = await buildInstalle();
    if (build != null) VersionApp.annoncer(app: cleApp, plateforme: plateforme, build: build);
    VersionApp.surMiseAJourRequise = (lien) => afficherEcranRequis(lien: lien);
  }

  /// Version plus récente proposée par Google Play à ce téléphone (pour le
  /// bandeau seulement) ; null si aucune, ou Play muet (app installée hors
  /// Play Store, pas de Play Store, plus de 4 s). Remplacé dans les tests.
  @visibleForTesting
  static Future<int?> Function() demanderAPlay = _demanderAPlay;

  static Future<int?> _demanderAPlay() async {
    // Vraie plateforme (pas defaultTargetPlatform, qui vaut Android dans les
    // tests) : ailleurs, aucun appel natif.
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final info = await InAppUpdate.checkForUpdate().timeout(const Duration(seconds: 4));
      final disponible = info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress;
      return disponible ? info.availableVersionCode : null;
    } catch (_) {
      return null;
    }
  }

  /// Une course (ou une livraison) est en cours : on ne bloque pas.
  /// Remplacé dans les tests.
  @visibleForTesting
  static Future<bool> Function() verifierCourse = courseSelonServeur;

  /// Le serveur tranche : sous la minimale, il répond 426 à toute requête,
  /// sauf pendant une course ou une livraison en cours (et, pour le client,
  /// juste terminée : paiement, note). 426 : aucune course. Toute autre réponse (il laisse
  /// passer) ou le doute (réseau) : on considère qu'il y en a une. Pas
  /// connecté : aucune course possible.
  static Future<bool> courseSelonServeur() async {
    if (!ApiService.estConnecte) return false;
    final refusAvant = VersionApp.refusRecus;
    try {
      await ApiService.mesDemandesAssignees().timeout(const Duration(seconds: 12));
      return true;
    } catch (_) {
      return VersionApp.refusRecus == refusAvant;
    }
  }

  /// Bandeau « nouvelle version » : écouté au-dessus de tous les écrans.
  static final ValueNotifier<bool> bandeauVisible = ValueNotifier(false);
  static int? _cibleBandeau;
  static const String _cleBandeauFerme = 'mise_a_jour_bandeau_ferme';

  static DateTime? _derniereVerification;
  static const Duration intervalleRetour = Duration(minutes: 10);

  /// Écran de démarrage : faut-il bloquer ? Prépare aussi le bandeau.
  static Future<bool> doitBloquer({DateTime? maintenant}) async {
    _derniereVerification = maintenant ?? DateTime.now();
    final reponses = await Future.wait<Object?>([
      ConfigApp.attendreRafraichissement(),
      demanderAPlay(),
      buildInstalle(),
    ]);
    final installe = reponses[2] as int?;
    final cible = ConfigApp.cible(cleApp, plateforme);
    final bloquer = etat(installe: installe, cible: cible) == EtatMiseAJour.requise &&
        ficheConnue(cible.lien) &&
        !await verifierCourse();
    // L'écran bloquant suffit : jamais le bandeau par-dessus.
    await _preparerBandeau(
      bloquer || ecranAffiche ? null : cibleBandeau(installe: installe, cible: cible, versionPlay: reponses[1] as int?),
    );
    return bloquer;
  }

  /// Retour au premier plan : même vérification, au plus toutes les
  /// [intervalleRetour] (une requête de configuration, mise en cache).
  static Future<void> verifierAuRetour({DateTime? maintenant}) async {
    final instant = maintenant ?? DateTime.now();
    final derniere = _derniereVerification;
    if (derniere != null && instant.difference(derniere) < intervalleRetour) return;
    unawaited(ConfigApp.rafraichir());
    if (await doitBloquer(maintenant: instant)) afficherEcranRequis();
  }

  @visibleForTesting
  static void reinitialiser() {
    _derniereVerification = null;
    _cibleBandeau = null;
    _build = null;
    bandeauVisible.value = false;
    _ecranAffiche = false;
    lienServeur = null;
  }

  static Future<void> _preparerBandeau(int? cible) async {
    _cibleBandeau = cible;
    if (cible == null) {
      bandeauVisible.value = false;
      return;
    }
    int? fermee;
    try {
      fermee = (await SharedPreferences.getInstance()).getInt(_cleBandeauFerme);
    } catch (_) {
      // Illisible : le bandeau s'affiche.
    }
    bandeauVisible.value = fermee == null || cible > fermee;
  }

  /// Fermé : il ne revient que pour une version plus récente que la plus
  /// récente déjà écartée.
  static Future<void> fermerBandeau() async {
    bandeauVisible.value = false;
    final cible = _cibleBandeau;
    if (cible == null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final fermee = preferences.getInt(_cleBandeauFerme);
      if (fermee == null || cible > fermee) await preferences.setInt(_cleBandeauFerme, cible);
    } catch (_) {
      // Non gardé : il reviendra au prochain lancement.
    }
  }

  /// L'écran bloquant est affiché, ou sur le point de l'être : jamais deux.
  static bool get ecranAffiche => _ecranAffiche;
  static bool _ecranAffiche = false;

  /// Fiche du store envoyée par le serveur avec sa réponse 426.
  static String? lienServeur;

  /// Ouvre l'écran bloquant, seul à l'écran : les écrans dessous (et leurs
  /// requêtes périodiques) s'arrêtent. Sans risque pour une course : le
  /// serveur ne répond jamais 426 pendant une course, et le démarrage comme
  /// le retour au premier plan ne bloquent qu'après lui (courseSelonServeur).
  /// [navigateur] : celui de l'appelant (écran de démarrage), sinon celui de
  /// l'app (navigatorKey).
  static void afficherEcranRequis({String? lien, NavigatorState? navigateur}) {
    if (lien != null) lienServeur = lien;
    if (_ecranAffiche) return;
    if (!ficheConnue(lienServeur ?? ConfigApp.cible(cleApp, plateforme).lien)) return;
    final cible = navigateur ?? navigatorKey.currentState;
    if (cible == null) return;
    // Tout de suite, pas à la construction de l'écran : une deuxième 426
    // reçue dans la même frame n'en empile pas un deuxième.
    _ecranAffiche = true;
    bandeauVisible.value = false;
    cible
        .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const PageMiseAJourRequise()), (_) => false)
        .whenComplete(() => _ecranAffiche = false);
  }

  /// Bouton « Mettre à jour » : la mise à jour plein écran de Google Play
  /// (téléchargement, installation, redémarrage), sinon la fiche du store.
  static Future<IssueMiseAJour> mettreAJour() async {
    final integree = await _miseAJourIntegree();
    if (integree != null) return integree;
    return await ouvrirFiche() ? IssueMiseAJour.lancee : IssueMiseAJour.impossible;
  }

  /// Null : impossible depuis l'app (iOS, installée hors Play Store, Play
  /// muet, échec de Play), la fiche du store prend le relais.
  static Future<IssueMiseAJour?> _miseAJourIntegree() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      // Play exige une vérification juste avant de lancer la mise à jour.
      final info = await InAppUpdate.checkForUpdate().timeout(const Duration(seconds: 4));
      final reprise = info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress;
      final possible = info.updateAvailability == UpdateAvailability.updateAvailable && info.immediateUpdateAllowed;
      if (!reprise && !possible) return null;
      return switch (await InAppUpdate.performImmediateUpdate()) {
        AppUpdateResult.success => IssueMiseAJour.lancee,
        AppUpdateResult.userDeniedUpdate => IssueMiseAJour.annulee,
        AppUpdateResult.inAppUpdateFailed => null,
      };
    } catch (_) {
      return null;
    }
  }

  /// Fiche de l'app : le lien du serveur (App Store pour iOS), sinon le Play
  /// Store (l'app Play Store si elle est là, sinon le site).
  static Future<bool> ouvrirFiche() async {
    final lien = lienServeur ?? ConfigApp.cible(cleApp, plateforme).lien;
    final adresses = [
      if (lien != null) Uri.parse(lien),
      if (plateforme == 'android') ...[
        Uri.parse('market://details?id=$_paquet'),
        Uri.https('play.google.com', '/store/apps/details', {'id': _paquet}),
      ],
    ];
    for (final adresse in adresses) {
      try {
        if (await launchUrl(adresse, mode: LaunchMode.externalApplication)) return true;
      } catch (_) {
        // Suivante.
      }
    }
    return false;
  }
}
