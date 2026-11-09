// lib/services/mise_a_jour.dart
//
// Mise à jour obligatoire. Le serveur fixe le plus petit numéro de build encore
// accepté (config-app, version_min, réglé dans l'admin APRÈS chaque publication).
// En dessous, l'app s'arrête au démarrage sur « Mise à jour requise », qui mène
// au Play Store. Jamais pendant une course ou une livraison : l'app s'ouvre
// alors normalement et le blocage attend le lancement suivant.

import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'config_app.dart';

class MiseAJour {
  MiseAJour._();

  /// Clé de cette app dans version_min.
  static const String cleApp = 'chauffeur';
  static const String _paquet = 'com.taama.taama_conducteur';

  /// Course acceptée (ou prix en attente du client) : le chauffeur doit pouvoir
  /// la mener à terme. Une simple proposition ne compte pas : sans réponse, elle
  /// passe au suivant après 60 s.
  static const Set<String> statutsCourseEnCours = {'contre_offre', 'en_route', 'client_a_bord'};
  static const Set<String> statutsLivraisonEnCours = {'livreur_assigne', 'en_collecte', 'en_livraison'};

  /// Le build installé est connu et sous le minimum du serveur. Build inconnu ou
  /// minimum à 0 : jamais de blocage.
  static bool requise({required int? installe, required int minimum}) =>
      installe != null && minimum > 0 && installe < minimum;

  /// Une course ou une livraison est en cours.
  static bool courseEnCours(List<dynamic> demandes, List<dynamic> livraisons) =>
      demandes.any((d) => d is Map && statutsCourseEnCours.contains(d['statut'])) ||
      livraisons.any((l) => l is Map && statutsLivraisonEnCours.contains(l['statut']));

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

  /// Appelé par l'écran de démarrage, juste avant d'ouvrir l'app.
  static Future<bool> doitBloquer() async {
    await ConfigApp.attendreRafraichissement();
    final minimum = ConfigApp.versionsMin.value[cleApp] ?? 0;
    if (!requise(installe: await buildInstalle(), minimum: minimum)) return false;
    return !await _courseEnCours();
  }

  static Future<bool> _courseEnCours() async {
    if (!ApiService.estConnecte) return false;
    try {
      const delai = Duration(seconds: 12);
      final reponses = await Future.wait([
        ApiService.mesDemandesAssignees().timeout(delai),
        ApiService.mesLivraisonsCourier().timeout(delai),
      ]);
      return courseEnCours(reponses[0], reponses[1]);
    } catch (_) {
      // Impossible de vérifier : une course est peut-être en cours, on ne bloque pas.
      return true;
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
