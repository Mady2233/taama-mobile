// Écran Compte, « Se déconnecter » : confirmation d'abord ; refus pendant une
// course connue de l'app (sans requête) ou sur 409 ; sinon déconnecté, écran
// de connexion, même sans réponse du serveur (et il le dit).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_app/screens/compte_screen.dart';
import 'package:taama_app/screens/connexion_screen.dart';
import 'package:taama_app/services/api_service.dart';
import 'package:taama_app/services/courses_en_cours.dart';
import 'package:taama_app/services/deconnexion.dart';
import 'package:taama_app/services/notification_service.dart';
import 'package:taama_app/widgets/dialogue_deconnexion.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.definirToken('session-a');
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

  /// Ouvre l'écran, touche « Se déconnecter » ; rend les en-têtes reçus par
  /// la déconnexion. [code] null : réseau coupé.
  /// [course], [livraison] : statut rendu par le serveur à la relecture de
  /// la course 7 ou de la livraison 42 (null : réseau coupé).
  Future<List<String>> deconnecter(WidgetTester t,
      {int? code = 200, String? course, String? livraison, bool confirmer = true}) async {
    final recues = <String>[];
    await http.runWithClient(() async {
      await t.pumpWidget(const MaterialApp(home: EcranCompte()));
      await t.pump();
      await t.ensureVisible(find.text('Se déconnecter'));
      await t.tap(find.text('Se déconnecter'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Se déconnecter ?'), findsOneWidget);
      expect(find.text('Tu seras déconnecté de Taama sur tous tes appareils.'), findsOneWidget);
      await t.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(confirmer ? 'Se déconnecter' : 'Annuler'),
      ));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.runAsync(() => Deconnexion.tachesTerminees);
      await t.pump(const Duration(seconds: 1));
    }, () => MockClient((requete) async {
          if (requete.url.path.endsWith('/comptes/deconnexion/')) {
            recues.add(requete.headers['Authorization'] ?? '-');
            if (code == null) throw http.ClientException('Réseau coupé');
            return http.Response('{}', code);
          }
          for (final (chemin, statut) in [('/trajets/demandes/7/', course), ('/trajets/courier/42/', livraison)]) {
            if (!requete.url.path.endsWith(chemin)) continue;
            if (statut == null) throw http.ClientException('Réseau coupé');
            return http.Response('{"statut": "$statut"}', 200);
          }
          return http.Response('{"telephone": "+22376000000", "first_name": "Awa"}', 200);
        }));
    return recues;
  }

  testWidgets('course connue de l’app, encore en cours : message, pas de déconnexion envoyée', (t) async {
    await CoursesEnCours.enregistrerCourse(7);
    expect(await deconnecter(t, course: 'en_route'), isEmpty);
    expect(find.text(Deconnexion.messageCourseEnCours), findsOneWidget);
    expect(find.byType(EcranCompte), findsOneWidget);
    expect(ApiService.token, 'session-a');
  });

  testWidgets('course connue de l’app, serveur injoignable : refus, jamais hors réseau', (t) async {
    await CoursesEnCours.enregistrerCourse(7);
    expect(await deconnecter(t), isEmpty);
    expect(find.text(Deconnexion.messageCourseEnCours), findsOneWidget);
    expect(find.byType(EcranCompte), findsOneWidget);
    expect(ApiService.token, 'session-a');
  });

  testWidgets('livraison quittée puis livrée : relue sur le serveur, la déconnexion passe', (t) async {
    await CoursesEnCours.enregistrerLivraison(42);
    expect(await deconnecter(t, livraison: 'livre'), ['Token session-a']);
    expect(find.byType(EcranConnexion), findsOneWidget);
    expect(ApiService.estConnecte, isFalse);
  });

  testWidgets('409 du serveur : message, toujours connecté', (t) async {
    expect(await deconnecter(t, code: 409), ['Token session-a']);
    expect(find.text(Deconnexion.messageCourseEnCours), findsOneWidget);
    expect(find.byType(EcranCompte), findsOneWidget);
    expect(ApiService.token, 'session-a');
  });

  testWidgets('Annuler : rien n’est envoyé, toujours connecté', (t) async {
    expect(await deconnecter(t, confirmer: false), isEmpty);
    expect(find.byType(EcranCompte), findsOneWidget);
    expect(ApiService.token, 'session-a');
  });

  testWidgets('200 : déconnecté, écran de connexion, sans message hors réseau', (t) async {
    expect(await deconnecter(t), ['Token session-a']);
    expect(find.byType(EcranConnexion), findsOneWidget);
    expect(ApiService.estConnecte, isFalse);
    expect(find.text(messageDeconnexionHorsReseau), findsNothing);
  });

  testWidgets('réseau coupé : déconnecté quand même, retrait de l’appareil à faire', (t) async {
    expect(await deconnecter(t, code: null), ['Token session-a']);
    expect(find.byType(EcranConnexion), findsOneWidget);
    expect(find.text(messageDeconnexionHorsReseau), findsOneWidget);
    expect(ApiService.estConnecte, isFalse);
    expect(await Deconnexion.appareilsEnAttente(),
        [const AppareilARetirer(session: 'session-a', notification: 'jeton-firebase')]);
  });
}
