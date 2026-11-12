// Déconnexion depuis l'espace chauffeur (deconnecterChauffeur) : une course
// connue bloque sans requête ; une liste illisible est relue une fois (12 s au
// plus) ; toujours illisible, le chauffeur choisit de rester connecté ou de se
// déconnecter quand même. Dialogues : textes validés par l'utilisateur.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/services/api_service.dart';
import 'package:taama_conducteur/services/deconnexion.dart';
import 'package:taama_conducteur/services/deconnexion_chauffeur.dart';
import 'package:taama_conducteur/services/notification_service.dart';
import 'package:taama_conducteur/widgets/dialogue_deconnexion.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.definirToken('session-a');
    NotificationService.reinitialiserJeton();
    NotificationService.token = 'jeton-firebase';
    Deconnexion.reinitialiser();
    Deconnexion.supprimerJetonFirebase = () async {};
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.chargerTokenPersiste();
    NotificationService.reinitialiserJeton();
    Deconnexion.reinitialiser();
  });

  group('ce que l’espace sait de ses courses', () {
    EtatCoursesChauffeur etat(List<dynamic> demandes, bool demandesAJour, List<dynamic> livraisons, bool livraisonsAJour) =>
        etatCoursesChauffeur(
          demandes: demandes,
          demandesAJour: demandesAJour,
          livraisons: livraisons,
          livraisonsAJour: livraisonsAJour,
        );
    final course = {'id': 7, 'statut': 'en_route'};

    test('listes vides et lues : aucune course', () {
      expect(etat([], true, [], true), EtatCoursesChauffeur.aucune);
    });

    test('une course ou une livraison : en cours, même si la dernière lecture a échoué', () {
      expect(etat([course], true, [], true), EtatCoursesChauffeur.enCours);
      expect(etat([], true, [course], true), EtatCoursesChauffeur.enCours);
      expect(etat([course], false, [], false), EtatCoursesChauffeur.enCours);
    });

    test('une liste vide jamais lue ou en échec : inconnu, jamais « aucune »', () {
      expect(etat([], false, [], true), EtatCoursesChauffeur.inconnu);
      expect(etat([], true, [], false), EtatCoursesChauffeur.inconnu);
      expect(etat([], false, [], false), EtatCoursesChauffeur.inconnu);
    });

    test('401 ou 403 : réponse définitive ; réseau ou 5xx : non', () {
      expect(lectureDefinitive(ApiException(401, 'Session fermée')), isTrue);
      expect(lectureDefinitive(ApiException(403, 'Aucun profil chauffeur')), isTrue);
      expect(lectureDefinitive(ApiException(500, 'Erreur')), isFalse);
      expect(lectureDefinitive(http.ClientException('Réseau coupé')), isFalse);
    });
  });

  /// Lance deconnecterChauffeur ; rend l'issue, les requêtes reçues et le
  /// nombre de questions posées au chauffeur.
  Future<(IssueDeconnexion?, List<String>, int)> deconnecter({
    required EtatCoursesChauffeur Function() etat,
    Future<void> Function()? relire,
    bool quandMeme = false,
  }) async {
    final recues = <String>[];
    var questions = 0;
    late IssueDeconnexion? issue;
    await http.runWithClient(() async {
      issue = await deconnecterChauffeur(
        etat: etat,
        relire: relire ?? () async {},
        seDeconnecterQuandMeme: () async {
          questions++;
          return quandMeme;
        },
      );
      await Deconnexion.tachesTerminees;
    }, () => MockClient((requete) async {
          recues.add(requete.url.path.replaceFirst(RegExp(r'^.*/api'), ''));
          return http.Response('{}', 200);
        }));
    return (issue, recues, questions);
  }

  test('courses illisibles, même relues, et le chauffeur reste : rien n’est envoyé', () async {
    final (issue, recues, questions) = await deconnecter(etat: () => EtatCoursesChauffeur.inconnu);
    expect(issue, isNull);
    expect(questions, 1);
    expect(recues, isEmpty);
    expect(ApiService.token, 'session-a');
  });

  test('courses illisibles : « Se déconnecter quand même » déconnecte', () async {
    final (issue, recues, questions) =
        await deconnecter(etat: () => EtatCoursesChauffeur.inconnu, quandMeme: true);
    expect(questions, 1);
    expect(issue, IssueDeconnexion.deconnecte);
    expect(recues, ['/comptes/deconnexion/']);
    expect(ApiService.estConnecte, isFalse);
  });

  test('relecture réussie : aucune question, déconnexion envoyée', () async {
    var lu = false;
    final (issue, recues, questions) = await deconnecter(
      etat: () => lu ? EtatCoursesChauffeur.aucune : EtatCoursesChauffeur.inconnu,
      relire: () async => lu = true,
    );
    expect(questions, 0);
    expect(issue, IssueDeconnexion.deconnecte);
    expect(recues, ['/comptes/deconnexion/']);
  });

  test('course en cours : refus sans requête ni question', () async {
    final (issue, recues, questions) = await deconnecter(etat: () => EtatCoursesChauffeur.enCours);
    expect(issue, IssueDeconnexion.courseEnCours);
    expect(questions, 0);
    expect(recues, isEmpty);
    expect(ApiService.token, 'session-a');
  });

  testWidgets('relecture muette : 12 s au plus, puis la question', (t) async {
    var questions = 0;
    var fini = false;
    unawaited(deconnecterChauffeur(
      etat: () => EtatCoursesChauffeur.inconnu,
      relire: () => Completer<void>().future,
      seDeconnecterQuandMeme: () async {
        questions++;
        return false;
      },
    ).then((_) => fini = true));
    await t.pump(const Duration(seconds: 11));
    expect(questions, 0);
    await t.pump(const Duration(seconds: 2));
    expect(questions, 1);
    expect(fini, isTrue);
  });

  Future<bool?> ouvrir(WidgetTester t, Future<bool> Function(BuildContext) dialogue, String bouton,
      {List<String> textes = const []}) async {
    bool? reponse;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => reponse = await dialogue(context),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    for (final texte in textes) {
      expect(find.text(texte), findsOneWidget, reason: texte);
    }
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(bouton)));
    await t.pumpAndSettle();
    return reponse;
  }

  testWidgets('confirmation : textes validés, « Se déconnecter » confirme, Annuler non', (t) async {
    const textes = [
      'Se déconnecter ?',
      'Tu ne recevras plus de courses sur ce téléphone. Tu seras aussi déconnecté de Taama sur tes autres appareils.',
    ];
    expect(await ouvrir(t, demanderConfirmationDeconnexion, 'Se déconnecter', textes: textes), isTrue);
    expect(await ouvrir(t, demanderConfirmationDeconnexion, 'Annuler'), isFalse);
  });

  testWidgets('courses illisibles : avertissement, « Se déconnecter quand même » ou Annuler', (t) async {
    const textes = [
      'Impossible de vérifier tes courses. Vérifie ton réseau et réessaie.',
      'Si tu as une course en cours, tu ne pourras plus la suivre.',
    ];
    expect(await ouvrir(t, demanderDeconnexionQuandMeme, 'Se déconnecter quand même', textes: textes), isTrue);
    expect(await ouvrir(t, demanderDeconnexionQuandMeme, 'Annuler'), isFalse);
  });

  test('message hors réseau : texte validé', () {
    expect(messageDeconnexionHorsReseau,
        'Ce téléphone est déconnecté. Sans réseau, tu restes connecté sur tes autres téléphones.');
  });
}
