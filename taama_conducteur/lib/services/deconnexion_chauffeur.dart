// lib/services/deconnexion_chauffeur.dart
//
// Déconnexion depuis l'espace chauffeur. Ses deux listes (demandes et
// livraisons, mêmes statuts que ceux qui bloquent côté serveur) décident
// d'abord : une course connue bloque, sans requête. Une liste qui n'a pas pu
// être lue ne prouve rien : elle est relue une fois (12 s au plus). Toujours
// illisible, le chauffeur choisit : rester connecté, ou se déconnecter quand
// même. Jamais de déconnexion hors réseau pendant une course sur une liste
// vide faute de réseau, sans qu'il l'ait voulu.

import 'api_service.dart';
import 'deconnexion.dart';

enum EtatCoursesChauffeur { aucune, enCours, inconnu }

/// Réponse définitive du serveur à la lecture d'une liste : session déjà
/// fermée (401) ou compte sans profil chauffeur (403). Aucune course à
/// protéger ici : la liste vaut vide, jamais « inconnu » (le serveur vérifie
/// encore le reste à la déconnexion).
bool lectureDefinitive(Object erreur) =>
    erreur is ApiException && (erreur.statusCode == 401 || erreur.statusCode == 403);

/// Ce que l'espace sait des courses du chauffeur. Une liste non vide : en
/// cours, même si sa dernière lecture a échoué. Une liste vide jamais lue, ou
/// dont la dernière lecture a échoué : inconnu.
EtatCoursesChauffeur etatCoursesChauffeur({
  required List<dynamic> demandes,
  required bool demandesAJour,
  required List<dynamic> livraisons,
  required bool livraisonsAJour,
}) {
  if (demandes.isNotEmpty || livraisons.isNotEmpty) return EtatCoursesChauffeur.enCours;
  if (!demandesAJour || !livraisonsAJour) return EtatCoursesChauffeur.inconnu;
  return EtatCoursesChauffeur.aucune;
}

/// Déconnecte le chauffeur (Deconnexion.seDeconnecter). [etat] : ce que
/// l'espace sait de ses courses ; [relire] : relit ses deux listes ;
/// [seDeconnecterQuandMeme] : listes toujours illisibles, la question au
/// chauffeur. Nul : il reste connecté, à sa demande.
Future<IssueDeconnexion?> deconnecterChauffeur({
  required EtatCoursesChauffeur Function() etat,
  required Future<void> Function() relire,
  required Future<bool> Function() seDeconnecterQuandMeme,
}) async {
  var connu = etat();
  if (connu == EtatCoursesChauffeur.inconnu) {
    try {
      await relire().timeout(const Duration(seconds: 12));
    } catch (_) {
      // Toujours illisible : la question ci-dessous.
    }
    connu = etat();
  }
  if (connu == EtatCoursesChauffeur.inconnu && !await seDeconnecterQuandMeme()) return null;
  return Deconnexion.seDeconnecter(courseEnCoursLocale: connu == EtatCoursesChauffeur.enCours);
}
