// Suggestions de destinations à partir des lieux embarqués dans l'app, sans
// réseau. Un lieu choisi part avec ses coordonnées : jamais de prix calculé sur
// un point deviné par le géocodage.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/screens/recherche_screen.dart';
import 'package:taama_app/services/recherche_lieux.dart';

void main() {
  group('rechercherLieux', () {
    test('moins de 2 caractères : rien', () {
      expect(rechercherLieux(''), isEmpty);
      expect(rechercherLieux('b'), isEmpty);
      expect(rechercherLieux('  '), isEmpty);
    });

    test('début de nom d’abord, grand quartier en tête', () {
      final noms = rechercherLieux('bada').map((l) => l.nom).toList();
      expect(noms.first, 'Badalabougou');
      expect(noms, contains('Badalabougou Est'));
    });

    test('sans accents ni majuscules', () {
      expect(rechercherLieux('GRAND MARCHE').first.nom, 'Grand Marché');
      expect(rechercherLieux('gabriel').map((l) => l.nom), contains('Hopital Gabriel Toure'));
    });

    test('plusieurs mots, dans n’importe quel ordre', () {
      expect(rechercherLieux('toure gabriel').map((l) => l.nom), contains('Hopital Gabriel Toure'));
    });

    test('aucun résultat : liste vide, jamais d’invention', () {
      expect(rechercherLieux('zzzzzz'), isEmpty);
    });

    test('nombre de résultats plafonné', () {
      expect(rechercherLieux('ecobank').length, lessThanOrEqualTo(8));
      expect(rechercherLieux('ecobank', max: 3).length, 3);
    });

    test('noms en double : distingués par le quartier, avec leurs coordonnées', () {
      final ecobanks = rechercherLieux('ecobank');
      expect(ecobanks.length, greaterThan(1));
      expect(ecobanks.map((l) => l.detail).toSet().length, ecobanks.length);
      expect(ecobanks.first.detail, startsWith('Banque · '));
      expect(ecobanks.first.adresse, startsWith('${ecobanks.first.nom}, '));
    });

    test('un quartier reste « Quartier », et l’adresse reste son nom', () {
      final lieu = rechercherLieux('badalabougou').first;
      expect(lieu.detail, 'Quartier');
      expect(lieu.adresse, 'Badalabougou');
    });

    test('toujours des coordonnées dans Bamako', () {
      for (final saisie in const ['bada', 'marche', 'hopital', 'kalaban']) {
        for (final lieu in rechercherLieux(saisie)) {
          expect(lieu.lat, inInclusiveRange(12.4, 12.8));
          expect(lieu.lng, inInclusiveRange(-8.2, -7.8));
        }
      }
    });
  });

  group('lieuExact', () {
    test('nom unique : ses coordonnées', () {
      expect(lieuExact('badalabougou')?.nom, 'Badalabougou');
    });
    test('plusieurs endroits du même nom : pas de devinette', () {
      expect(lieuExact('Ecobank'), isNull);
    });
    test('inconnu ou vide : null', () {
      expect(lieuExact('zzzzzz'), isNull);
      expect(lieuExact('  '), isNull);
    });
  });

  test('géocodage d’une saisie libre limité au Grand Bamako', () {
    final uri = uriGeocodage('Rue 123');
    expect(uri.host, 'nominatim.openstreetmap.org');
    expect(uri.queryParameters['q'], 'Rue 123, Bamako, Mali');
    expect(uri.queryParameters['bounded'], '1');
    expect(uri.queryParameters['viewbox'], '-8.25,12.85,-7.70,12.30');
    expect(uri.queryParameters['limit'], '1');
  });

  group('écran de recherche', () {
    Future<List<DestinationChoisie?>> ouvrir(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final resultats = <DestinationChoisie?>[];
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              resultats.add(await Navigator.push<DestinationChoisie>(
                context,
                MaterialPageRoute(builder: (_) => const EcranRecherche()),
              ));
            },
            child: const Text('ouvrir'),
          ),
        ),
      ));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      return resultats;
    }

    testWidgets('sans saisie : les sections habituelles', (t) async {
      await ouvrir(t);
      expect(find.text('Destinations populaires'), findsOneWidget);
    });

    testWidgets('choisir une suggestion renvoie le lieu et ses coordonnées', (t) async {
      final resultats = await ouvrir(t);
      await t.enterText(find.byType(TextField).first, 'badala');
      await t.pump();

      expect(find.text('Destinations populaires'), findsNothing);
      expect(find.text('Badalabougou'), findsOneWidget);

      await t.tap(find.text('Badalabougou'));
      await t.pumpAndSettle();

      expect(resultats.single?.nom, 'Badalabougou');
      expect(resultats.single?.lat, isNotNull);
      expect(resultats.single?.lng, isNotNull);
    });

    testWidgets('aucun lieu : message, et la saisie libre reste possible', (t) async {
      final resultats = await ouvrir(t);
      await t.enterText(find.byType(TextField).first, 'zzzzzz');
      await t.pump();

      expect(find.textContaining('Aucun lieu connu'), findsOneWidget);
      await t.tap(find.text('Utiliser « zzzzzz »'));
      await t.pumpAndSettle();

      expect(resultats.single?.nom, 'zzzzzz');
      expect(resultats.single?.lat, isNull);
    });
  });
}
