// Courses et livraisons en cours connues de l'app (CoursesEnCours) :
// enregistrées, effacées à leur fin, relues par l'accueil, gardées sur le
// téléphone, expirées 2 h après.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_app/services/api_service.dart';
import 'package:taama_app/services/courses_en_cours.dart';

void main() {
  // Heure réelle : les entrées expirées sont purgées à chaque écriture.
  final t0 = DateTime.now();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rien d’enregistré : rien en cours', () async {
    expect(await CoursesEnCours.enCours(maintenant: t0), isFalse);
  });

  test('course : en cours dès sa création, plus après sa fin', () async {
    await CoursesEnCours.enregistrerCourse(7, maintenant: t0);
    expect(await CoursesEnCours.enCours(maintenant: t0), isTrue);
    await CoursesEnCours.effacerCourse(7);
    expect(await CoursesEnCours.enCours(maintenant: t0), isFalse);
  });

  test('livraison : de même, sans toucher aux courses', () async {
    await CoursesEnCours.enregistrerLivraison(9, maintenant: t0);
    await CoursesEnCours.effacerCourse(9);
    expect(await CoursesEnCours.enCours(maintenant: t0), isTrue);
    await CoursesEnCours.effacerLivraison(9);
    expect(await CoursesEnCours.enCours(maintenant: t0), isFalse);
  });

  test('expiration de sécurité : plus en cours 2 h après', () async {
    await CoursesEnCours.enregistrerCourse(7, maintenant: t0);
    expect(await CoursesEnCours.enCours(maintenant: t0.add(const Duration(hours: 1, minutes: 59))), isTrue);
    expect(await CoursesEnCours.enCours(maintenant: t0.add(const Duration(hours: 2))), isFalse);
  });

  test('horloge reculée : une date dans le futur expire de même', () async {
    await CoursesEnCours.enregistrerCourse(7, maintenant: t0);
    expect(await CoursesEnCours.enCours(maintenant: t0.subtract(const Duration(hours: 3))), isFalse);
  });

  test('gardée sur le téléphone : toujours là au lancement suivant', () async {
    await CoursesEnCours.enregistrerCourse(7, maintenant: t0);
    final garde = (await SharedPreferences.getInstance()).getString(CoursesEnCours.cle);
    SharedPreferences.setMockInitialValues({CoursesEnCours.cle: garde!});
    expect(await CoursesEnCours.enCours(maintenant: t0.add(const Duration(minutes: 30))), isTrue);
  });

  test('accueil sans course en cours : les courses sont effacées, les livraisons restent', () async {
    await CoursesEnCours.enregistrerCourse(7, maintenant: t0);
    await CoursesEnCours.enregistrerLivraison(9, maintenant: t0);
    final lecture = t0.add(const Duration(minutes: 1));
    await CoursesEnCours.remplacerCourses(null, lueLe: lecture, maintenant: lecture);
    expect(await CoursesEnCours.enCours(maintenant: lecture), isTrue);
    await CoursesEnCours.effacerLivraison(9);
    expect(await CoursesEnCours.enCours(maintenant: lecture), isFalse);
  });

  test('accueil : une course commandée pendant sa lecture est gardée', () async {
    final lecture = t0;
    await CoursesEnCours.enregistrerCourse(8, maintenant: t0.add(const Duration(seconds: 5)));
    await CoursesEnCours.remplacerCourses(null, lueLe: lecture, maintenant: t0.add(const Duration(seconds: 6)));
    expect(await CoursesEnCours.enCours(maintenant: t0.add(const Duration(seconds: 6))), isTrue);
  });

  test('accueil : la course retrouvée sur le serveur est enregistrée', () async {
    await CoursesEnCours.remplacerCourses(12, lueLe: t0, maintenant: t0);
    expect(await CoursesEnCours.enCours(maintenant: t0), isTrue);
    await CoursesEnCours.effacerCourse(12);
    expect(await CoursesEnCours.enCours(maintenant: t0), isFalse);
  });

  test('tout effacé après la déconnexion', () async {
    await CoursesEnCours.enregistrerCourse(7, maintenant: t0);
    await CoursesEnCours.enregistrerLivraison(9, maintenant: t0);
    await CoursesEnCours.toutEffacer();
    expect(await CoursesEnCours.enCours(maintenant: t0), isFalse);
  });

  /// Relecture : le serveur rend [statuts] par chemin (null : réseau coupé).
  Future<(bool, List<String>)> relire(Map<String, String?> statuts) async {
    final chemins = <String>[];
    late bool enCours;
    await http.runWithClient(() async {
      enCours = await CoursesEnCours.enCoursApresRelecture(maintenant: t0);
    }, () => MockClient((requete) async {
          final chemin = requete.url.path.replaceFirst(RegExp(r'^.*/api'), '');
          chemins.add(chemin);
          final statut = statuts[chemin];
          if (statut == null) throw http.ClientException('Réseau coupé');
          return http.Response('{"id": 1, "statut": "$statut"}', 200);
        }));
    return (enCours, chemins);
  }

  test('relecture : rien de connu, aucune requête', () async {
    final (enCours, chemins) = await relire({});
    expect(enCours, isFalse);
    expect(chemins, isEmpty);
  });

  test('relecture : livraison livrée et course terminée effacées, la déconnexion passe', () async {
    await ApiService.definirToken('session-a');
    await CoursesEnCours.enregistrerLivraison(42, maintenant: t0);
    await CoursesEnCours.enregistrerCourse(7, maintenant: t0);
    final (enCours, chemins) = await relire({
      '/trajets/courier/42/': 'livre',
      '/trajets/demandes/7/': 'annule',
    });
    expect(enCours, isFalse);
    expect(chemins, unorderedEquals(['/trajets/courier/42/', '/trajets/demandes/7/']));
    expect(await CoursesEnCours.enCours(maintenant: t0), isFalse);
  });

  test('relecture : livraison sans livreur (en recherche), effacée, la déconnexion passe', () async {
    await ApiService.definirToken('session-a');
    await CoursesEnCours.enregistrerLivraison(42, maintenant: t0);
    expect((await relire({'/trajets/courier/42/': 'en_recherche'})).$1, isFalse);
    expect(await CoursesEnCours.enCours(maintenant: t0), isFalse);
  });

  test('relecture : livraison attribuée, elle compte toujours', () async {
    await ApiService.definirToken('session-a');
    await CoursesEnCours.enregistrerLivraison(42, maintenant: t0);
    expect((await relire({'/trajets/courier/42/': 'livreur_assigne'})).$1, isTrue);
  });

  test('relecture : 401 (session fermée ailleurs), plus rien ne bloque la déconnexion', () async {
    await ApiService.definirToken('session-a');
    await CoursesEnCours.enregistrerCourse(7, maintenant: t0);
    late bool enCours;
    await http.runWithClient(() async {
      enCours = await CoursesEnCours.enCoursApresRelecture(maintenant: t0);
    }, () => MockClient((_) async => http.Response('{"detail": "Jeton invalide."}', 401)));
    expect(enCours, isFalse);
  });

  test('relecture : encore en cours, ou sans réponse, elle compte toujours', () async {
    await ApiService.definirToken('session-a');
    await CoursesEnCours.enregistrerCourse(7, maintenant: t0);
    expect((await relire({'/trajets/demandes/7/': 'client_a_bord'})).$1, isTrue);
    expect((await relire({})).$1, isTrue); // réseau coupé
    expect(await CoursesEnCours.enCours(maintenant: t0), isTrue);
  });

  test('valeur illisible : rien en cours, sans erreur', () async {
    SharedPreferences.setMockInitialValues({CoursesEnCours.cle: 'pas du json'});
    expect(await CoursesEnCours.enCours(maintenant: t0), isFalse);
    await CoursesEnCours.enregistrerCourse(7, maintenant: t0);
    expect(await CoursesEnCours.enCours(maintenant: t0), isTrue);
  });
}
