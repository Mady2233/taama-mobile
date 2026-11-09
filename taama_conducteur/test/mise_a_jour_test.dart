// Mise à jour obligatoire : bloquée dès que Google Play propose une version plus
// récente, ou sous le minimum du serveur (lu et gardé) ; jamais pendant une
// course ; écran sans retour avec deux boutons qui marchent.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/screens/mise_a_jour_requise_screen.dart';
import 'package:taama_conducteur/services/config_app.dart';
import 'package:taama_conducteur/services/mise_a_jour.dart';

http.Client _reponse(String corps) => MockClient((_) async => http.Response(corps, 200));

void main() {
  final demanderAPlay = MiseAJour.demanderAPlay;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConfigApp.versionsMin.value = const {};
  });

  tearDown(() => MiseAJour.demanderAPlay = demanderAPlay);

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

    test('version plus récente sur Google Play : bloqué, sans rien régler dans l’admin', () {
      expect(MiseAJour.bloquer(installe: 61, minimum: 0, surPlay: true), isTrue);
      expect(MiseAJour.bloquer(installe: null, minimum: 0, surPlay: true), isTrue);
    });

    test('Play à jour ou muet : seul le minimum du serveur décide', () {
      expect(MiseAJour.bloquer(installe: 61, minimum: 0, surPlay: false), isFalse);
      expect(MiseAJour.bloquer(installe: 61, minimum: 0, surPlay: null), isFalse);
      expect(MiseAJour.bloquer(installe: 60, minimum: 61, surPlay: null), isTrue,
          reason: 'app installée hors Play Store : le serveur reste le filet de secours');
      expect(MiseAJour.bloquer(installe: 60, minimum: 61, surPlay: false), isTrue);
    });

    test('réponse de Google Play : une mise à jour interrompue doit être reprise', () {
      expect(MiseAJour.plusRecenteSurPlay(UpdateAvailability.updateAvailable), isTrue);
      expect(MiseAJour.plusRecenteSurPlay(UpdateAvailability.developerTriggeredUpdateInProgress), isTrue);
      expect(MiseAJour.plusRecenteSurPlay(UpdateAvailability.updateNotAvailable), isFalse);
      expect(MiseAJour.plusRecenteSurPlay(UpdateAvailability.unknown), isNull);
    });

    test('au démarrage : Play et serveur ensemble', () async {
      PackageInfo.setMockInitialValues(
        appName: 'Taama Conducteur', packageName: 'com.taama.taama_conducteur', version: '1.0.0',
        buildNumber: '61', buildSignature: '',
      );
      MiseAJour.demanderAPlay = () async => true;
      expect(await MiseAJour.doitBloquer(), isTrue);

      MiseAJour.demanderAPlay = () async => null;
      expect(await MiseAJour.doitBloquer(), isFalse);

      ConfigApp.versionsMin.value = const {'chauffeur': 62};
      expect(await MiseAJour.doitBloquer(), isTrue);
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
    Future<List<String>> ouvrir(
      WidgetTester t, {
      AvisMiseAJour? avis,
      bool enCours = false,
      Size taille = const Size(360, 780),
    }) async {
      await t.binding.setSurfaceSize(taille);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final actions = <String>[];
      await t.pumpWidget(MaterialApp(
        home: EcranMiseAJourRequise(
          onMettreAJour: () => actions.add('maj'),
          onReessayer: () => actions.add('reessayer'),
          avis: avis,
          enCours: enCours,
        ),
      ));
      return actions;
    }

    Future<void> toucher(WidgetTester t, String texte) async {
      await t.ensureVisible(find.text(texte));
      await t.pump();
      await t.tap(find.text(texte));
    }

    testWidgets('message et deux boutons qui marchent', (t) async {
      final actions = await ouvrir(t);
      expect(find.text('Nouvelle version disponible'), findsOneWidget);
      await toucher(t, 'Mettre à jour');
      await toucher(t, 'Réessayer');
      expect(actions, ['maj', 'reessayer']);
    });

    testWidgets('petit écran : rien ne déborde, les boutons restent accessibles', (t) async {
      final actions = await ouvrir(t, avis: AvisMiseAJour.annulee, taille: const Size(320, 480));
      expect(t.takeException(), isNull);
      await toucher(t, 'Mettre à jour');
      expect(actions, ['maj']);
    });

    testWidgets('aucun retour possible', (t) async {
      await ouvrir(t);
      expect(t.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    });

    testWidgets('Google Play en cours d’ouverture : aucun second envoi', (t) async {
      final actions = await ouvrir(t, enCours: true);
      expect(find.text('Ouverture de Google Play…'), findsOneWidget);
      expect(find.text('Mettre à jour'), findsNothing);
      await toucher(t, 'Ouverture de Google Play…');
      await toucher(t, 'Réessayer');
      expect(actions, isEmpty);
    });

    testWidgets('mise à jour annulée : le dire', (t) async {
      await ouvrir(t, avis: AvisMiseAJour.annulee);
      expect(find.textContaining('Mise à jour annulée'), findsOneWidget);
    });

    testWidgets('Play Store indisponible : le dire', (t) async {
      await ouvrir(t, avis: AvisMiseAJour.playStoreIndisponible);
      expect(find.textContaining('Le Play Store ne s’est pas ouvert'), findsOneWidget);
    });
  });
}
