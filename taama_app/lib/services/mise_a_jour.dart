// lib/services/mise_a_jour.dart
//
// Mise à jour obligatoire. Au démarrage, l'app s'arrête sur « Mettre à jour »
// dès que Google Play propose une version plus récente à ce téléphone : Play ne
// la propose qu'une fois téléchargeable, personne n'est bloqué sans rien à
// installer. Filet de secours : le plus petit numéro de build fixé par le
// serveur (config-app, version_min, réglé dans l'admin), qui vaut aussi pour
// une app installée hors Play Store. Jamais pendant une course : avec une
// course en cours, l'app s'ouvre normalement et le blocage attend le
// lancement suivant.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'config_app.dart';

/// Issue du bouton « Mettre à jour ».
enum IssueMiseAJour {
  /// Google Play installe la nouvelle version (l'app redémarre d'elle-même),
  /// ou sa fiche s'est ouverte.
  lancee,

  /// L'utilisateur a fermé l'écran de Google Play.
  annulee,

  /// Ni la mise à jour intégrée ni la fiche du Play Store n'ont pu s'ouvrir.
  impossible,
}

class MiseAJour {
  MiseAJour._();

  /// Clé de cette app dans version_min.
  static const String cleApp = 'client';
  static const String _paquet = 'com.taama.taama_app';

  /// Course pas encore terminée : le client la suit, rien ne doit l'en empêcher.
  static const Set<String> statutsCourseEnCours = {
    'en_recherche', 'chauffeur_trouve', 'contre_offre', 'en_route', 'client_a_bord',
  };

  /// Le build installé est connu et sous le minimum du serveur. Build inconnu ou
  /// minimum à 0 : jamais de blocage.
  static bool requise({required int? installe, required int minimum}) =>
      installe != null && minimum > 0 && installe < minimum;

  /// Bloquer l'ouverture : Google Play a une version plus récente, ou le
  /// serveur exige un build plus récent. Play muet (null) : seul le serveur
  /// décide.
  static bool bloquer({required int? installe, required int minimum, required bool? surPlay}) =>
      surPlay == true || requise(installe: installe, minimum: minimum);

  /// Lecture de la réponse de Google Play. Une mise à jour lancée puis
  /// interrompue compte comme disponible : elle doit être reprise.
  static bool? plusRecenteSurPlay(UpdateAvailability disponibilite) => switch (disponibilite) {
        UpdateAvailability.updateAvailable || UpdateAvailability.developerTriggeredUpdateInProgress => true,
        UpdateAvailability.updateNotAvailable => false,
        UpdateAvailability.unknown => null,
      };

  /// Une des demandes est une course en cours.
  static bool courseEnCours(List<dynamic> demandes) =>
      demandes.any((d) => d is Map && statutsCourseEnCours.contains(d['statut']));

  /// Null si illisible ou trop lent (2 s) : l'app s'ouvre alors normalement,
  /// jamais un démarrage bloqué.
  static Future<int?> buildInstalle() async {
    try {
      final info = await PackageInfo.fromPlatform().timeout(const Duration(seconds: 2));
      return int.tryParse(info.buildNumber);
    } catch (_) {
      return null;
    }
  }

  /// Google Play a-t-il une version plus récente pour ce téléphone ? Null si
  /// Play ne répond pas (app installée hors Play Store, pas de Play Store,
  /// plus de 4 s) : jamais de blocage pour ce seul motif. Remplacé dans les
  /// tests.
  @visibleForTesting
  static Future<bool?> Function() demanderAPlay = _demanderAPlay;

  static Future<bool?> _demanderAPlay() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await InAppUpdate.checkForUpdate().timeout(const Duration(seconds: 4));
      return plusRecenteSurPlay(info.updateAvailability);
    } catch (_) {
      return null;
    }
  }

  /// Appelé par l'écran de démarrage, juste avant d'ouvrir l'app. Serveur et
  /// Google Play sont interrogés en même temps : aucune attente de plus.
  static Future<bool> doitBloquer() async {
    final reponses = await Future.wait<Object?>([
      ConfigApp.attendreRafraichissement(),
      demanderAPlay(),
      buildInstalle(),
    ]);
    final minimum = ConfigApp.versionsMin.value[cleApp] ?? 0;
    final bloque = bloquer(
      installe: reponses[2] as int?,
      minimum: minimum,
      surPlay: reponses[1] as bool?,
    );
    if (!bloque) return false;
    return !await _courseEnCours();
  }

  static Future<bool> _courseEnCours() async {
    if (!ApiService.estConnecte) return false;
    try {
      final demandes = await ApiService.mesDemandesClient().timeout(const Duration(seconds: 12));
      return courseEnCours(demandes);
    } catch (_) {
      // Impossible de vérifier : une course est peut-être en cours, on ne bloque pas.
      return true;
    }
  }

  /// Bouton « Mettre à jour » : la mise à jour plein écran de Google Play
  /// (téléchargement, installation, redémarrage), sinon la fiche du Play Store.
  static Future<IssueMiseAJour> mettreAJour() async {
    final integree = await _miseAJourIntegree();
    if (integree != null) return integree;
    return await ouvrirPlayStore() ? IssueMiseAJour.lancee : IssueMiseAJour.impossible;
  }

  /// Null : impossible depuis l'app (installée hors Play Store, Play muet,
  /// échec de Play), la fiche du Play Store prend le relais.
  static Future<IssueMiseAJour?> _miseAJourIntegree() async {
    if (!Platform.isAndroid) return null;
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

  /// Fiche Play Store de l'app : l'app Play Store si elle est là, sinon le site.
  static Future<bool> ouvrirPlayStore() async {
    try {
      if (await launchUrl(Uri.parse('market://details?id=$_paquet'), mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Pas d'app Play Store : le site ci-dessous.
    }
    try {
      return await launchUrl(
        Uri.https('play.google.com', '/store/apps/details', {'id': _paquet}),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
