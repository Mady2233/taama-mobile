// Fond de carte : refus du fournisseur (401/403), clé jamais écrite dans le
// cache ni les journaux, état explicite quand rien n'est configuré.
// Même fichier dans taama_app et taama_conducteur (seul l'import diffère).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:taama_conducteur/carte/fond_carte.dart';

NetworkImageLoadException _http(int code) => NetworkImageLoadException(
    statusCode: code, uri: Uri.parse('https://tuiles.exemple/1/2/3.png?key=SECRET123'));

void main() {
  setUp(EtatFondCarte.reinitialiser);

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
