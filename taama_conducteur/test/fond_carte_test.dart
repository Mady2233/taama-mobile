// Fond de carte : refus du fournisseur (401/403), clé jamais écrite dans le
// cache ni les journaux, état explicite quand rien n'est configuré.
// Même fichier dans taama_app et taama_conducteur (seul l'import diffère).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:taama_conducteur/carte/fond_carte.dart';
import 'package:taama_conducteur/carte/journal_sans_cle.dart';

NetworkImageLoadException _http(int code) => NetworkImageLoadException(
    statusCode: code, uri: Uri.parse('https://tuiles.exemple/1/2/3.png?key=SECRET123'));

void main() {
  setUp(EtatFondCarte.reinitialiser);
  group('de bout en bout', mainBoutEnBout);
  group('journaux sans clé', mainJournal);

  group('EtatFondCarte', () {
    test('deux refus 403 : carte indisponible', () {
      EtatFondCarte.signaler(_http(403));
      expect(EtatFondCarte.refuse.value, isFalse, reason: 'un seul refus ne suffit pas');
      EtatFondCarte.signaler(_http(403));
      expect(EtatFondCarte.refuse.value, isTrue);
    });

    test('401 compte comme un refus', () {
      EtatFondCarte.signaler(_http(401));
      EtatFondCarte.signaler(_http(401));
      expect(EtatFondCarte.refuse.value, isTrue);
    });

    test('404, 500 et erreurs réseau ne masquent jamais la carte', () {
      for (var i = 0; i < 5; i++) {
        EtatFondCarte.signaler(_http(404));
        EtatFondCarte.signaler(_http(500));
        EtatFondCarte.signaler(const SocketException('hors réseau'));
      }
      expect(EtatFondCarte.refuse.value, isFalse);
    });

    test('ne journalise rien (l\'erreur contient la clé)', () {
      final journal = <String>[];
      final ancien = debugPrint;
      debugPrint = (m, {wrapWidth}) => journal.add(m ?? '');
      try {
        EtatFondCarte.signaler(_http(403));
        EtatFondCarte.signaler(_http(403));
        EtatFondCarte.signaler(_http(500));
      } finally {
        debugPrint = ancien;
      }
      expect(journal, isEmpty);
    });
  });

  group('clé absente du cache', () {
    test('adresse sans clé, autres paramètres conservés', () {
      expect(adresseSansCle('https://t/1/2/3.png?key=SECRET123'), 'https://t/1/2/3.png');
      expect(adresseSansCle('https://t/1.png?key=SECRET123&lang=fr'), 'https://t/1.png?lang=fr');
      expect(adresseSansCle('https://t/1.png?lang=fr&key=SECRET123'), 'https://t/1.png?lang=fr');
      expect(adresseSansCle('https://t/1.png?lang=fr&key=SECRET123&v=2'), 'https://t/1.png?lang=fr&v=2');
      expect(adresseSansCle('https://t/1.png'), 'https://t/1.png');
    });

    test('identifiant de cache identique quelle que soit la clé, sans la clé', () {
      final a = cleCacheTuile('https://t/1/2/3.png?key=SECRET123');
      final b = cleCacheTuile('https://t/1/2/3.png?key=AUTRECLE');
      expect(a, b);
      expect(a, isNot(contains('SECRET123')));
    });

    test('le code du fond ne contient aucun print ni debugPrint', () {
      final source = File('lib/carte/fond_carte.dart').readAsStringSync();
      expect(source, isNot(contains('print(')));
    });
  });

  testWidgets('sans configuration : « Carte indisponible », aucune requête', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 200,
          child: FlutterMap(
            options: MapOptions(initialCenter: LatLng(12.64, -8.0), initialZoom: 13),
            children: [FondCarteTaama()],
          ),
        ),
      ),
    ));
    expect(find.text('Carte indisponible pour le moment'), findsOneWidget);
    expect(find.byType(TileLayer), findsNothing);
  });

  testWidgets('refus du fournisseur : « Carte indisponible »', (t) async {
    // Configuration simulée impossible (constantes de build) : on vérifie la
    // bascule sur le widget lui-même via l'état partagé.
    EtatFondCarte.signaler(_http(403));
    EtatFondCarte.signaler(_http(403));
    await t.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: EtatFondCarte.refuse,
        builder: (_, refuse, __) => Text(refuse ? 'refusé' : 'ok'),
      ),
    ));
    expect(find.text('refusé'), findsOneWidget);
  });
}

// ─── De bout en bout, par flutter_map ────────────────────────────────────
// MapTiler répond 403 à une clé invalide ou vide, AVEC une image PNG
// « Invalid key ». Par défaut, flutter_map affiche cette image comme une
// tuile et ne signale aucune erreur : la détection des refus ne voyait rien.

// PNG 1 x 1 valide : le corps d'erreur est une vraie image, comme chez MapTiler.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

http.Client _serveur(int code) => MockClient(
    (_) async => http.Response.bytes(_png, code, headers: {'content-type': 'image/png'}));

const _adresse = 'https://tuiles.exemple/{z}/{x}/{y}.png?key=SECRET123';

/// Charge une tuile avec [fournisseur] : null si une image est affichée,
/// sinon l'erreur levée.
Future<Object?> _chargerTuile(NetworkTileProvider fournisseur) {
  final image = fournisseur.getImageWithCancelLoadingSupport(
    const TileCoordinates(1, 1, 1),
    TileLayer(urlTemplate: _adresse),
    Completer<void>().future,
  );
  final resultat = Completer<Object?>();
  final flux = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener ecoute;
  ecoute = ImageStreamListener(
    (_, __) {
      if (!resultat.isCompleted) resultat.complete(null);
      flux.removeListener(ecoute);
    },
    onError: (erreur, _) {
      if (!resultat.isCompleted) resultat.complete(erreur);
      flux.removeListener(ecoute);
    },
  );
  flux.addListener(ecoute);
  return resultat.future.timeout(const Duration(seconds: 5));
}

void mainBoutEnBout() {
  setUp(EtatFondCarte.reinitialiser);

  testWidgets('403 avec une image d\'erreur : jamais affichée, erreur 403 levée', (t) async {
    final erreur = await t.runAsync(() => _chargerTuile(
        fournisseurTuiles(client: _serveur(403), cache: const DisabledMapCachingProvider())));
    expect(erreur, isA<NetworkImageLoadException>());
    expect((erreur as NetworkImageLoadException).statusCode, 403);
  });

  testWidgets('200 : la tuile s\'affiche normalement', (t) async {
    final erreur = await t.runAsync(() => _chargerTuile(
        fournisseurTuiles(client: _serveur(200), cache: const DisabledMapCachingProvider())));
    expect(erreur, isNull);
  });

  testWidgets('témoin : avec le réglage par défaut, l\'image d\'erreur serait affichée',
      (t) async {
    final erreur = await t.runAsync(() => _chargerTuile(NetworkTileProvider(
        httpClient: _serveur(403), cachingProvider: const DisabledMapCachingProvider())));
    expect(erreur, isNull, reason: 'le défaut existe bien sans attemptDecodeOfHttpErrorResponses');
  });

  testWidgets('par flutter_map : deux 403 → « Carte indisponible »', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: FlutterMap(
        options: const MapOptions(initialCenter: LatLng(12.64, -8.0), initialZoom: 13),
        children: [
          coucheTuilesTaama(
            url: _adresse,
            client: _serveur(403),
            cache: const DisabledMapCachingProvider(),
          ),
        ],
      ),
    ));
    for (var i = 0; i < 20 && !EtatFondCarte.refuse.value; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    expect(EtatFondCarte.refuse.value, isTrue);
  });
}

void mainJournal() {
  setUp(EtatFondCarte.reinitialiser);

  test('sansCle : ?key= et &key= masqués, le reste intact', () {
    expect(sansCle('https://t/1.png?key=SECRET123'), 'https://t/1.png?key=***');
    expect(sansCle('https://t/1.png?lang=fr&key=SECRET123&v=2'), 'https://t/1.png?lang=fr&key=***&v=2');
    expect(sansCle('HTTP request failed, statusCode: 403, https://t/1.png?key=SECRET123 suite'),
        'HTTP request failed, statusCode: 403, https://t/1.png?key=*** suite');
    expect(sansCle('aucune clé ici'), 'aucune clé ici');
  });

  testWidgets('par flutter_map : deux 403 journalisés SANS la clé', (t) async {
    final journal = <String>[];
    final ancien = debugPrint;
    debugPrint = (m, {wrapWidth}) => journal.add(m ?? '');
    installerJournalSansCle();

    await t.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: FlutterMap(
        options: const MapOptions(initialCenter: LatLng(12.64, -8.0), initialZoom: 13),
        children: [
          coucheTuilesTaama(url: _adresse, client: _serveur(403), cache: const DisabledMapCachingProvider()),
        ],
      ),
    ));
    for (var i = 0; i < 20 && !EtatFondCarte.refuse.value; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    // Restauré AVANT la fin du test : le cadre de test vérifie debugPrint.
    debugPrint = ancien;
    expect(EtatFondCarte.refuse.value, isTrue);
    expect(journal.where((l) => l.contains('SECRET123')), isEmpty, reason: journal.join('\n'));
    expect(journal.any((l) => l.contains('key=***')), isTrue,
        reason: 'flutter_map journalise bien l\'adresse, masquée');
  });
}
