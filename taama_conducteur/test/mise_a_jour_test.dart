// Mise à jour : versions minimale et recommandée lues sur le serveur (par app
// et par plateforme) et gardées ; sous la minimale, écran bloquant ; sous la
// recommandée (ou version plus récente sur Google Play), bandeau qu'on peut
// fermer ; jamais pendant une course (le serveur tranche par sa réponse 426) ;
// un seul écran bloquant, seul à l'écran ; serveur injoignable : dernière valeur,
// sinon rien n'est exigé ; vérification au retour au premier plan, au plus
// toutes les 10 min ; version annoncée au serveur, et sa réponse 426.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/screens/mise_a_jour_requise_page.dart';
import 'package:taama_conducteur/screens/mise_a_jour_requise_screen.dart';
import 'package:taama_conducteur/screens/splash_screen.dart';
import 'package:taama_conducteur/services/api_service.dart';
import 'package:taama_conducteur/services/config_app.dart';
import 'package:taama_conducteur/services/demande_entrante_navigator.dart';
import 'package:taama_conducteur/services/mise_a_jour.dart';
import 'package:taama_conducteur/services/version_app.dart';
import 'package:taama_conducteur/widgets/bandeau_mise_a_jour.dart';

const _app = 'chauffeur';

http.Client _reponse(String corps) => MockClient((_) async => http.Response(corps, 200));

String _config({int minimale = 0, int recommandee = 0, int iosMinimale = 0, String? iosLien}) =>
    '{"paiement_actif": false, '
    '"version_min": {"client": 0, "chauffeur": $minimale}, '
    '"versions": {"$_app": {"android": {"minimale": $minimale, "recommandee": $recommandee, '
    '"lien": "https://play.google.com/store/apps/details?id=x"}, '
    '"ios": {"minimale": $iosMinimale, "recommandee": 0, "lien": ${iosLien == null ? 'null' : '"$iosLien"'}}}}}';

void main() {
  final demanderAPlay = MiseAJour.demanderAPlay;
  final verifierCourse = MiseAJour.verifierCourse;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Taama', packageName: 'x', version: '1.0.0', buildNumber: '64', buildSignature: '',
    );
    ConfigApp.versionsMin.value = const {};
    ConfigApp.versions.value = const {};
    MiseAJour.reinitialiser();
    MiseAJour.demanderAPlay = () async => null;
    MiseAJour.verifierCourse = () async => false;
    VersionApp.surMiseAJourRequise = null;
  });

  tearDown(() {
    MiseAJour.demanderAPlay = demanderAPlay;
    MiseAJour.verifierCourse = verifierCourse;
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> regler({int minimale = 0, int recommandee = 0, int iosMinimale = 0, String? iosLien}) =>
      ConfigApp.rafraichir(client: _reponse(_config(
        minimale: minimale, recommandee: recommandee, iosMinimale: iosMinimale, iosLien: iosLien)));

  group('versions du serveur', () {
    test('minimale, recommandée et fiche, par app et par plateforme', () async {
      await regler(minimale: 62, recommandee: 66);
      final cible = ConfigApp.cible(_app, 'android');
      expect((cible.minimale, cible.recommandee), (62, 66));
      expect(cible.lien, startsWith('https://'));
      expect(ConfigApp.cible(_app, 'ios').minimale, 0);
    });

    test('gardées pour le prochain lancement (même hors ligne)', () async {
      await regler(minimale: 62, recommandee: 66);
      ConfigApp.versions.value = const {};
      await ConfigApp.chargerValeurGardee();
      expect(ConfigApp.cible(_app, 'android').recommandee, 66);
    });

    test('serveur injoignable : la dernière valeur connue reste', () async {
      await regler(minimale: 62, recommandee: 66);
      await ConfigApp.rafraichir(client: MockClient((_) async => throw const SocketExceptionFactice()));
      expect(ConfigApp.cible(_app, 'android').minimale, 62);
    });

    test('jamais connue : rien n’est exigé', () {
      final cible = ConfigApp.cible(_app, 'android');
      expect((cible.minimale, cible.recommandee), (0, 0));
    });

    test('ancien serveur (version_min seul) : la minimale Android, sans bandeau', () async {
      await ConfigApp.rafraichir(client: _reponse('{"version_min": {"chauffeur": 61}}'));
      final cible = ConfigApp.cible(_app, 'android');
      expect((cible.minimale, cible.recommandee), (61, 0));
      expect(ConfigApp.cible(_app, 'ios').minimale, 0);
    });

    test('valeurs invalides ignorées', () async {
      await ConfigApp.rafraichir(client: _reponse(
          '{"versions": {"chauffeur": {"android": {"minimale": "61", "recommandee": -1}}}}'));
      expect(ConfigApp.cible(_app, 'android').minimale, 0);
    });

    test('l’attente au démarrage est bornée', () async {
      unawaited(ConfigApp.rafraichir(client: MockClient((_) => Completer<http.Response>().future)));
      final debut = DateTime.now();
      await ConfigApp.attendreRafraichissement(delai: const Duration(milliseconds: 100));
      expect(DateTime.now().difference(debut), lessThan(const Duration(seconds: 2)));
    });
  });

  group('décision', () {
    const cible = VersionsCible(minimale: 62, recommandee: 66);

    test('sous la minimale : requise', () {
      expect(MiseAJour.etat(installe: 61, cible: cible), EtatMiseAJour.requise);
    });

    test('entre la minimale et la recommandée : recommandée', () {
      expect(MiseAJour.etat(installe: 62, cible: cible), EtatMiseAJour.recommandee);
      expect(MiseAJour.etat(installe: 65, cible: cible), EtatMiseAJour.recommandee);
    });

    test('à jour', () {
      expect(MiseAJour.etat(installe: 66, cible: cible), EtatMiseAJour.aJour);
      expect(MiseAJour.etat(installe: 80, cible: cible), EtatMiseAJour.aJour);
    });

    test('build inconnu ou versions à 0 : jamais bloqué', () {
      expect(MiseAJour.etat(installe: null, cible: cible), EtatMiseAJour.aJour);
      expect(MiseAJour.etat(installe: 1, cible: const VersionsCible(minimale: 0, recommandee: 0)), EtatMiseAJour.aJour);
    });

    test('bandeau : la version la plus récente proposée', () {
      expect(MiseAJour.cibleBandeau(installe: 64, cible: cible), 66);
      expect(MiseAJour.cibleBandeau(installe: 64, cible: cible, versionPlay: 70), 70);
      expect(MiseAJour.cibleBandeau(installe: 66, cible: cible), isNull);
      expect(MiseAJour.cibleBandeau(installe: null, cible: cible), isNull);
    });

    test('clé de cette app', () => expect(MiseAJour.cleApp, _app));
  });

  group('au démarrage', () {
    test('sous la minimale : bloqué, sans bandeau par-dessus l’écran bloquant', () async {
      await regler(minimale: 65, recommandee: 66);
      expect(await MiseAJour.doitBloquer(), isTrue);
      expect(MiseAJour.bandeauVisible.value, isFalse);
    });

    test('iOS sans fiche du store : jamais bloqué (rien à installer)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await regler(iosMinimale: 70);
      expect(await MiseAJour.doitBloquer(), isFalse);
    });

    test('iOS avec sa fiche : bloqué', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await regler(iosMinimale: 70, iosLien: 'https://apps.apple.com/app/id000');
      expect(await MiseAJour.doitBloquer(), isTrue);
    });

    test('sous la minimale pendant une course : pas bloqué, le bandeau prévient', () async {
      await regler(minimale: 65);
      MiseAJour.verifierCourse = () async => true;
      expect(await MiseAJour.doitBloquer(), isFalse);
      expect(MiseAJour.bandeauVisible.value, isTrue);
    });

    test('entre les deux : pas bloqué, bandeau', () async {
      await regler(minimale: 62, recommandee: 66);
      expect(await MiseAJour.doitBloquer(), isFalse);
      expect(MiseAJour.bandeauVisible.value, isTrue);
    });

    test('à jour : rien', () async {
      await regler(minimale: 62, recommandee: 64);
      expect(await MiseAJour.doitBloquer(), isFalse);
      expect(MiseAJour.bandeauVisible.value, isFalse);
    });

    test('serveur jamais joint : rien', () async {
      expect(await MiseAJour.doitBloquer(), isFalse);
      expect(MiseAJour.bandeauVisible.value, isFalse);
    });

    test('Google Play propose une version plus récente : bandeau, jamais bloqué', () async {
      MiseAJour.demanderAPlay = () async => 70;
      expect(await MiseAJour.doitBloquer(), isFalse);
      expect(MiseAJour.bandeauVisible.value, isTrue);
    });

    test('bandeau fermé : il ne revient que pour une version plus récente', () async {
      await regler(recommandee: 66);
      await MiseAJour.doitBloquer();
      await MiseAJour.fermerBandeau();
      expect(MiseAJour.bandeauVisible.value, isFalse);
      await MiseAJour.doitBloquer();
      expect(MiseAJour.bandeauVisible.value, isFalse);
      await regler(recommandee: 67);
      await MiseAJour.doitBloquer();
      expect(MiseAJour.bandeauVisible.value, isTrue);
    });

    test('bandeau fermé : une version plus ancienne que celle écartée ne le rouvre pas', () async {
      await regler(recommandee: 66);
      MiseAJour.demanderAPlay = () async => 68;
      await MiseAJour.doitBloquer();
      await MiseAJour.fermerBandeau(); // 68 écartée
      MiseAJour.demanderAPlay = () async => null; // Play muet : la cible retombe à 66
      await MiseAJour.doitBloquer();
      expect(MiseAJour.bandeauVisible.value, isFalse);
      await MiseAJour.fermerBandeau(); // ne remplace pas 68 par 66
      MiseAJour.demanderAPlay = () async => 68;
      await MiseAJour.doitBloquer();
      expect(MiseAJour.bandeauVisible.value, isFalse);
    });
  });

  group('course en cours : le serveur tranche', () {
    setUp(() => ApiService.definirToken('jeton-essai'));

    tearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await ApiService.chargerTokenPersiste();
    });

    Future<bool> demander(Future<http.Response> Function() reponse) =>
        http.runWithClient(MiseAJour.courseSelonServeur, () => MockClient((_) => reponse()));

    test('réponse 426 « Mise à jour requise » : aucune course, on bloque', () async {
      expect(await demander(() async => http.Response('{"code": "MISE_A_JOUR_REQUISE"}', 426)), isFalse);
    });

    test('le serveur laisse passer (course en cours, ou version encore acceptée) : pas de blocage', () async {
      expect(await demander(() async => http.Response('[]', 200)), isTrue);
    });

    test('réseau en panne ou autre erreur : doute, pas de blocage', () async {
      expect(await demander(() async => throw const SocketExceptionFactice()), isTrue);
      expect(await demander(() async => http.Response('{"erreur": "panne"}', 500)), isTrue);
      expect(await demander(() async => http.Response('{"code": "AUTRE"}', 426)), isTrue);
    });

    test('pas connecté : aucune course possible', () async {
      SharedPreferences.setMockInitialValues({});
      await ApiService.chargerTokenPersiste();
      expect(await demander(() async => http.Response('[]', 200)), isFalse);
    });
  });

  group('écran bloquant', () {
    testWidgets('deux 426 dans la même frame : un seul écran, seul à l’écran, sans bandeau', (t) async {
      final observateur = _CompteurPoussees();
      await t.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observateur],
        home: const Text('accueil'),
      ));
      MiseAJour.bandeauVisible.value = true;
      MiseAJour.afficherEcranRequis();
      MiseAJour.afficherEcranRequis();
      expect(MiseAJour.bandeauVisible.value, isFalse);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(observateur.poussees, 2); // l'accueil, puis un seul écran bloquant
      expect(MiseAJour.ecranAffiche, isTrue);
      expect(find.byType(PageMiseAJourRequise), findsOneWidget);
      // Retiré de la pile, pas seulement caché dessous (ses minuteries s'arrêtent).
      expect(find.text('accueil', skipOffstage: false), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);
    });

    testWidgets('écran retiré : l’indicateur retombe, il peut se rouvrir', (t) async {
      await t.pumpWidget(MaterialApp(navigatorKey: navigatorKey, home: const Text('accueil')));
      MiseAJour.afficherEcranRequis();
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      unawaited(navigatorKey.currentState!
          .pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const Text('suite')), (_) => false));
      await t.pump(const Duration(seconds: 1));
      expect(MiseAJour.ecranAffiche, isFalse);
      MiseAJour.afficherEcranRequis();
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(PageMiseAJourRequise), findsOneWidget);
    });

    testWidgets('« Réessayer » relit la configuration, puis relance le démarrage', (t) async {
      await t.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(navigatorKey: navigatorKey, home: const Text('accueil')));
      MiseAJour.afficherEcranRequis();
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      var lectures = 0;
      await http.runWithClient(() async {
        await t.ensureVisible(find.text('Réessayer'));
        await t.pump();
        await t.tap(find.text('Réessayer'));
        await t.pump();
      }, () => MockClient((requete) async {
        if (requete.url.path.endsWith('/config-app/')) lectures++;
        return http.Response(_config(), 200);
      }));
      expect(lectures, 1);
      expect(MiseAJour.ecranAffiche, isFalse); // place au démarrage
      expect(find.byType(EcranSplash, skipOffstage: false), findsOneWidget);
      await t.pump(const Duration(seconds: 1)); // fin de la transition
      expect(find.byType(PageMiseAJourRequise, skipOffstage: false), findsNothing);
      // Le démarrage relancé, retiré à son tour, finit ses étapes sans rien animer.
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('iOS sans fiche du store : il ne s’ouvre pas', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await t.pumpWidget(MaterialApp(navigatorKey: navigatorKey, home: const Text('accueil')));
      MiseAJour.afficherEcranRequis();
      await t.pump();
      expect(MiseAJour.ecranAffiche, isFalse);
      expect(find.text('accueil'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('retour au premier plan', () {
    test('au plus toutes les 10 min', () async {
      var appels = 0;
      MiseAJour.demanderAPlay = () async {
        appels++;
        return null;
      };
      final debut = DateTime(2026, 11, 9, 10);
      await MiseAJour.verifierAuRetour(maintenant: debut);
      await MiseAJour.verifierAuRetour(maintenant: debut.add(const Duration(minutes: 5)));
      expect(appels, 1);
      await MiseAJour.verifierAuRetour(maintenant: debut.add(const Duration(minutes: 11)));
      expect(appels, 2);
    });
  });

  group('version annoncée au serveur', () {
    tearDown(VersionApp.oublier);

    test('en-tête « app/plateforme/build »', () async {
      await MiseAJour.annoncerVersion();
      expect(VersionApp.entetes(), {'X-Taama-App': '$_app/android/64'});
    });

    test('build inconnu : aucun en-tête (le serveur laisse passer)', () {
      VersionApp.oublier();
      expect(VersionApp.entetes(), isEmpty);
    });

    test('réponse 426 « Mise à jour requise » : l’écran est demandé', () {
      String? lienRecu;
      var appels = 0;
      VersionApp.surMiseAJourRequise = (lien) {
        appels++;
        lienRecu = lien;
      };
      expect(VersionApp.signaler(426, '{"code": "MISE_A_JOUR_REQUISE", "lien": "https://fiche"}'), isTrue);
      expect((appels, lienRecu), (1, 'https://fiche'));
      expect(VersionApp.signaler(426, '{"code": "AUTRE"}'), isFalse);
      expect(VersionApp.signaler(400, '{"code": "MISE_A_JOUR_REQUISE"}'), isFalse);
      expect(VersionApp.signaler(426, '<html>'), isFalse);
      expect(appels, 1);
    });

  });

  group('écran', () {
    Future<List<String>> ouvrir(WidgetTester t, {AvisMiseAJour? avis, bool enCours = false, bool ios = false}) async {
      await t.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final actions = <String>[];
      await t.pumpWidget(MaterialApp(
        home: EcranMiseAJourRequise(
          onMettreAJour: () => actions.add('maj'),
          onReessayer: () => actions.add('reessayer'),
          avis: avis,
          enCours: enCours,
          ios: ios,
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

    testWidgets('aucun retour possible', (t) async {
      await ouvrir(t);
      expect(t.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    });

    testWidgets('iPhone : l’App Store, jamais Google Play ni le Play Store', (t) async {
      await ouvrir(t, ios: true, avis: AvisMiseAJour.playStoreIndisponible, enCours: true);
      expect(find.textContaining('App Store'), findsWidgets);
      expect(find.textContaining('Google Play'), findsNothing);
      expect(find.textContaining('Play Store'), findsNothing);
    });

    testWidgets('Play Store indisponible : le dire', (t) async {
      await ouvrir(t, avis: AvisMiseAJour.playStoreIndisponible);
      expect(find.textContaining('Le Play Store ne s’est pas ouvert'), findsOneWidget);
    });
  });

  group('bandeau', () {
    Future<List<String>> ouvrir(WidgetTester t, {bool echec = false, double largeur = 393, bool ios = false}) async {
      await t.binding.setSurfaceSize(Size(largeur, 300));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final actions = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BandeauMiseAJour(
            onMettreAJour: () => actions.add('maj'),
            onFermer: () => actions.add('fermer'),
            echec: echec,
            ios: ios,
          ),
        ),
      ));
      return actions;
    }

    testWidgets('mettre à jour, ou fermer', (t) async {
      final actions = await ouvrir(t);
      expect(find.text('Nouvelle version disponible'), findsOneWidget);
      await t.tap(find.text('Mettre à jour'));
      await t.tap(find.byIcon(Icons.close_rounded));
      expect(actions, ['maj', 'fermer']);
      expect(t.widget<Icon>(find.byIcon(Icons.close_rounded)).semanticLabel, 'Fermer');
    });

    // Comme main.dart : au-dessus du Navigator, donc sans Overlay.
    testWidgets('au-dessus de tous les écrans : se construit, puis se ferme', (t) async {
      MiseAJour.bandeauVisible.value = true;
      await t.pumpWidget(MaterialApp(
        builder: (context, enfant) => AvecBandeauMiseAJour(child: enfant ?? const SizedBox.shrink()),
        home: const Scaffold(body: Text('accueil')),
      ));
      expect(t.takeException(), isNull);
      expect(find.text('accueil'), findsOneWidget);
      expect(find.text('Nouvelle version disponible'), findsOneWidget);
      await t.tap(find.byIcon(Icons.close_rounded));
      await t.pump();
      expect(find.text('Nouvelle version disponible'), findsNothing);
      expect(find.text('accueil'), findsOneWidget);
    });

    testWidgets('caché pendant une demande entrante (compte à rebours en haut)', (t) async {
      addTearDown(() => DemandeEntranteNavigator.ecransOuverts.value = 0);
      MiseAJour.bandeauVisible.value = true;
      await t.pumpWidget(MaterialApp(
        builder: (context, enfant) => AvecBandeauMiseAJour(child: enfant ?? const SizedBox.shrink()),
        home: const Scaffold(body: Text('accueil')),
      ));
      expect(find.text('Nouvelle version disponible'), findsOneWidget);
      DemandeEntranteNavigator.ecransOuverts.value = 1;
      await t.pump();
      expect(find.text('Nouvelle version disponible'), findsNothing);
      DemandeEntranteNavigator.ecransOuverts.value = 0;
      await t.pump();
      expect(find.text('Nouvelle version disponible'), findsOneWidget);
    });

    testWidgets('iPhone, fiche introuvable : l’App Store, jamais le Play Store', (t) async {
      await ouvrir(t, echec: true, ios: true);
      expect(find.textContaining('Ouvre l’App Store'), findsOneWidget);
      expect(find.textContaining('Play Store'), findsNothing);
    });

    testWidgets('fiche introuvable : le dire', (t) async {
      await ouvrir(t, echec: true);
      expect(find.textContaining('Ouvre le Play Store'), findsOneWidget);
    });

    testWidgets('petit écran : rien ne déborde', (t) async {
      await ouvrir(t, largeur: 320);
      expect(t.takeException(), isNull);
    });
  });
}

/// Erreur réseau simulée (le client HTTP lève, comme hors ligne).
class SocketExceptionFactice implements Exception {
  const SocketExceptionFactice();
}

/// Compte les écrans poussés, route initiale comprise.
class _CompteurPoussees extends NavigatorObserver {
  int poussees = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? precedente) => poussees++;
}
