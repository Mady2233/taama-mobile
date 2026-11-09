// Mise à jour obligatoire : version minimale lue sur le serveur et gardée, blocage
// seulement sous le minimum, jamais pendant une course, écran sans retour avec
// deux boutons qui marchent.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/screens/mise_a_jour_requise_screen.dart';
import 'package:taama_conducteur/services/config_app.dart';
import 'package:taama_conducteur/services/mise_a_jour.dart';

http.Client _reponse(String corps) => MockClient((_) async => http.Response(corps, 200));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConfigApp.versionsMin.value = const {};
  });

  group('versions minimales du serveur', () {
    test('lues, puis gardées pour le prochain lancement (même hors ligne)', () async {
      await ConfigApp.rafraichir(client: _reponse('{"paiement_actif": false, "version_min": {"client": 61, "chauffeur": 62}}'));
      expect(ConfigApp.versionsMin.value, {'client': 61, 'chauffeur': 62});

      ConfigApp.versionsMin.value = const {};
      await ConfigApp.chargerValeurGardee();
      expect(ConfigApp.versionsMin.value, {'client': 61, 'chauffeur': 62});
    });

    test('valeurs invalides ignorées', () async {
      await ConfigApp.rafraichir(client: _reponse('{"version_min": {"client": "61", "chauffeur": -1}}'));
      expect(ConfigApp.versionsMin.value, isEmpty);
    });

    test('champ absent (base du serveur injoignable) : la dernière valeur reste', () async {
      await ConfigApp.rafraichir(client: _reponse('{"version_min": {"client": 61}}'));
      await ConfigApp.rafraichir(client: _reponse('{"paiement_actif": false}'));
      expect(ConfigApp.versionsMin.value, {'client': 61});
    });

    test('serveur qui ne répond pas : l’attente au démarrage est bornée', () async {
      unawaited(ConfigApp.rafraichir(client: MockClient((_) => Completer<http.Response>().future)));
      final debut = DateTime.now();
      await ConfigApp.attendreRafraichissement(delai: const Duration(milliseconds: 100));
      expect(DateTime.now().difference(debut), lessThan(const Duration(seconds: 2)));
    });
  });

  group('décision', () {
    test('bloqué seulement sous le minimum', () {
      expect(MiseAJour.requise(installe: 60, minimum: 61), isTrue);
      expect(MiseAJour.requise(installe: 61, minimum: 61), isFalse);
      expect(MiseAJour.requise(installe: 62, minimum: 61), isFalse);
    });

    test('minimum à 0 ou build inconnu : jamais bloqué', () {
      expect(MiseAJour.requise(installe: 60, minimum: 0), isFalse);
      expect(MiseAJour.requise(installe: null, minimum: 61), isFalse);
    });

    test('jamais pendant une course ni une livraison', () {
      for (final statut in ['contre_offre', 'en_route', 'client_a_bord']) {
        expect(MiseAJour.courseEnCours([{'statut': statut}], const []), isTrue, reason: statut);
      }
      for (final statut in ['livreur_assigne', 'en_collecte', 'en_livraison']) {
        expect(MiseAJour.courseEnCours(const [], [{'statut': statut}]), isTrue, reason: statut);
      }
      expect(MiseAJour.courseEnCours([{'statut': 'termine'}], [{'statut': 'livre'}]), isFalse);
    });

    test('une simple proposition ne protège pas : elle passe au suivant sans réponse', () {
      expect(MiseAJour.courseEnCours([{'statut': 'chauffeur_trouve'}], const []), isFalse);
    });

    test('clé de cette app', () => expect(MiseAJour.cleApp, 'chauffeur'));
  });

  group('écran', () {
    Future<List<String>> ouvrir(WidgetTester t, {bool indisponible = false}) async {
      final actions = <String>[];
      await t.pumpWidget(MaterialApp(
        home: EcranMiseAJourRequise(
          onMettreAJour: () => actions.add('maj'),
          onReessayer: () => actions.add('reessayer'),
          playStoreIndisponible: indisponible,
        ),
      ));
      return actions;
    }

    testWidgets('message et deux boutons qui marchent', (t) async {
      final actions = await ouvrir(t);
      expect(find.text('Nouvelle version disponible'), findsOneWidget);
      await t.tap(find.text('Mettre à jour'));
      await t.tap(find.text('Réessayer'));
      expect(actions, ['maj', 'reessayer']);
    });

    testWidgets('aucun retour possible', (t) async {
      await ouvrir(t);
      expect(t.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    });

    testWidgets('Play Store indisponible : le dire', (t) async {
      await ouvrir(t, indisponible: true);
      expect(find.textContaining('Le Play Store ne s’est pas ouvert'), findsOneWidget);
    });
  });
}
