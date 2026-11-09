// Suggestions de destinations à partir des lieux embarqués dans l'app, sans
// réseau. Un lieu choisi part avec ses coordonnées : jamais de prix calculé sur
// un point deviné par le géocodage.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/screens/recherche_screen.dart';
import 'package:taama_app/services/recherche_lieux.dart';
import 'package:taama_app/widgets/champ_adresse_lieu.dart';

void main() {
  group('rechercherLieux', () {
    test('rien de saisi : rien', () {
      expect(rechercherLieux(''), isEmpty);
      expect(rechercherLieux('  '), isEmpty);
    });

    test('une lettre : les quartiers qui commencent par elle, jamais un repère', () {
      final lieux = rechercherLieux('b');
      expect(lieux, isNotEmpty);
      for (final lieu in lieux) {
        expect(normaliserLieu(lieu.nom), startsWith('b'));
        expect(lieu.detail, anyOf('Quartier', 'Localité'));
      }
    });

    test('une lettre sans quartier : vide, jamais un nom qui la contient', () {
      for (final lieu in rechercherLieux('y')) {
        expect(normaliserLieu(lieu.nom), startsWith('y'));
      }
    });

    test('les orthographes courantes trouvent le quartier', () {
      const attendus = {
        'Kalabancoura': 'Kalaban Coura',
        'Kalabankoura': 'Kalaban Coura',
        'Medina Koura': 'Médina-coura',
        'Magnanbougou': 'Magnambougou',
        'Maniambougou': 'Magnambougou',
        'Magnambugu': 'Magnambougou',
        'Kinzambougou': 'Quinzambougou',
        'Quinzanbougou': 'Quinzambougou',
        'Nyarela': 'Niaréla',
        'Faladje': 'Faladie',
        'Hamdalaye': 'Hamdallaye',
        'Amdallaye': 'Hamdallaye',
        'Baco djikoroni': 'Baco-Djicoroni',
        'Bako djicoroni': 'Baco-Djicoroni',
        'Darsalam': 'Dar Salam',
        'Daoudabugu': 'Daoudabougou',
        'Boulkasoumbougou': 'Boulkassoumbougou',
      };
      attendus.forEach((saisie, nom) {
        expect(rechercherLieux(saisie).first.nom, nom, reason: saisie);
      });
    });

    test('une faute de frappe : le nom le plus proche d’abord', () {
      expect(rechercherLieux('Sokoniko').first.nom, 'Sogoniko');
      expect(rechercherLieux('Boulkassombougou').first.nom, 'Boulkassoumbougou');
      expect(rechercherLieux('Tomikorobougou').first.nom, "N'Tomikirobougou");
    });

    test('bien écrit : le bon quartier reste en tête, sans quartier voisin ajouté', () {
      final noms = rechercherLieux('Kabala').map((l) => l.nom).toList();
      expect(noms.first, 'Kabala');
      expect(noms, isNot(contains('Kababougou')));
      expect(rechercherLieux('Sogoniko').first.nom, 'Sogoniko');
      expect(rechercherLieux('Hamdallaye').first.nom, 'Hamdallaye');
    });

    test('le nom identique passe devant les noms plus longs', () {
      expect(rechercherLieux('Kalaban Coura').first.nom, 'Kalaban Coura');
      expect(rechercherLieux('Lafiabougou').first.nom, 'Lafiabougou');
    });

    test('un nom trop court ne tolère aucune faute', () {
      expect(rechercherLieux('xoli'), isEmpty);
    });

    test('les localités du Grand Bamako sont trouvées, avec leurs coordonnées', () {
      for (final nom in const ['Moribabougou', 'Sangarebougou', 'Dialakorodji', 'Mountougoula', 'Kati']) {
        final lieu = rechercherLieux(nom).first;
        expect(lieu.nom, nom);
        expect(lieu.detail, 'Localité');
        expect(lieu.adresse, nom);
        expect(lieu.lat, inInclusiveRange(12.48, 12.77));
        expect(lieu.lng, inInclusiveRange(-8.12, -7.80));
      }
    });

    test('le nom de la ville seul n’est pas une destination', () {
      expect(rechercherLieux('Bamako').map((l) => l.nom), isNot(contains('Bamako')));
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

  group('rues', () {
    List<LieuTrouve> rue428(String saisie) =>
        rechercherLieux(saisie).where((l) => l.nom == 'Rue 428').toList();

    test('une rue numérotée, dans chacun de ses quartiers', () {
      final lieux = rue428('rue 428');
      expect(lieux.map((l) => l.detail).toSet().length, greaterThan(1));
      expect(lieux.map((l) => l.adresse), contains('Rue 428, Hamdallaye'));
    });

    test('écritures courantes : r428, rue428', () {
      expect(rue428('r428'), isNotEmpty);
      expect(rue428('rue428'), isNotEmpty);
    });

    test('abréviations : av, bd, rte', () {
      expect(rechercherLieux('av kasse').map((l) => l.nom), contains('Avenue Kasse Keita'));
      expect(rechercherLieux('rte koulikoro').map((l) => l.nom), contains('Route de Koulikoro'));
    });

    test('un numéro mal tapé ne propose jamais une autre rue', () {
      expect(rue428('rue 4289'), isEmpty);
      expect(rechercherLieux('rue 4289').where((l) => l.detail.startsWith('Voie')), isEmpty);
    });

    test('une lettre : jamais une rue', () {
      expect(rechercherLieux('r').where((l) => l.detail.startsWith('Voie')), isEmpty);
    });

    test('un quartier passe avant une rue qui porte son nom', () {
      expect(rechercherLieux('hamdallaye').first.detail, 'Quartier');
    });

    test('voie longue : point à préciser sur la carte ; voie courte : son point', () {
      final lieux = rue428('rue 428');
      final niarela = lieux.singleWhere((l) => l.adresse == 'Rue 428, Niaréla');
      final hamdallaye = lieux.singleWhere((l) => l.adresse == 'Rue 428, Hamdallaye');
      expect(niarela.aPreciser, isTrue);
      expect(niarela.detail, contains('point à préciser sur la carte'));
      expect(hamdallaye.aPreciser, isFalse);
    });

    test('un nom de rue tapé sans le choisir : jamais deviné', () {
      expect(lieuExact('Rue 428'), isNull);
    });
  });

  group('clePhonetique', () {
    String cle(String texte) => clePhonetique(normaliserLieu(texte));

    test('les écritures d’un même nom donnent la même clé', () {
      expect(cle('Kalabancoura'), cle('Kalaban Coura'));
      expect(cle('Magnanbougou'), cle('Maniambougou'));
      expect(cle('Djikoroni'), cle('Jikoroni'));
      expect(cle('Faladie'), cle('Faladje'));
      expect(cle('Kinzambougou'), cle('Quinzambougou'));
      expect(cle('Hamdalaye'), cle('Hamdallaye'));
    });

    test('des noms différents restent différents', () {
      expect(cle('Sogoniko'), isNot(cle('Sokorodji')));
      expect(cle('ACI 2000'), isNot(cle('ACI 20')));
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

    testWidgets('dès la première lettre : des quartiers', (t) async {
      await ouvrir(t);
      await t.enterText(find.byType(TextField).first, 'b');
      await t.pump();

      expect(find.text('Destinations populaires'), findsNothing);
      expect(find.text('Quartier'), findsWidgets);
    });

    testWidgets('une autre orthographe propose le quartier', (t) async {
      final resultats = await ouvrir(t);
      await t.enterText(find.byType(TextField).first, 'Kinzambougou');
      await t.pump();

      await t.tap(find.text('Quinzambougou'));
      await t.pumpAndSettle();

      expect(resultats.single?.nom, 'Quinzambougou');
      expect(resultats.single?.lat, isNotNull);
    });

    testWidgets('voie courte : choisie avec son point', (t) async {
      final resultats = await ouvrir(t);
      await t.enterText(find.byType(TextField).first, 'rue 428');
      await t.pump();

      await t.tap(find.text('Voie · Hamdallaye'));
      await t.pumpAndSettle();

      expect(resultats.single?.nom, 'Rue 428, Hamdallaye');
      expect(resultats.single?.lat, isNotNull);
    });

    testWidgets('voie longue : la carte s’ouvre pour préciser le point', (t) async {
      final resultats = await ouvrir(t);
      await t.enterText(find.byType(TextField).first, 'rue 428');
      await t.pump();

      await t.tap(find.text('Voie · Niaréla · point à préciser sur la carte'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));

      expect(find.text('Où exactement, Rue 428 ?'), findsOneWidget);
      expect(find.text('Confirmer la destination'), findsOneWidget);
      expect(resultats, isEmpty); // rien n'est choisi tant que le point n'est pas confirmé
    });

    testWidgets('choisir sur la carte : sans saisie comme pendant la saisie', (t) async {
      final resultats = await ouvrir(t);
      expect(find.text('Choisir sur la carte'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, 'zzzz');
      await t.pump();
      expect(find.text('Choisir sur la carte'), findsOneWidget);

      await t.tap(find.text('Choisir sur la carte'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));

      expect(find.text('Où allez-vous ?'), findsOneWidget);
      expect(find.text('Confirmer la destination'), findsOneWidget);
      expect(resultats, isEmpty); // rien n'est choisi tant que le point n'est pas confirmé
    });

    testWidgets('adresse « Domicile » : les suggestions apparaissent aussi', (t) async {
      await ouvrir(t);
      await t.tap(find.text('Domicile'));
      await t.pumpAndSettle();

      await t.enterText(find.byType(ChampAdresseLieu), 'Magnanbou');
      await t.pump();

      // Le nom existe aussi derrière le dialogue, dans les destinations populaires.
      expect(
        find.descendant(of: find.byType(ChampAdresseLieu), matching: find.text('Magnambougou')),
        findsOneWidget,
      );
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

  group('champ d’adresse avec suggestions', () {
    late List<LieuTrouve?> lieux;
    late TextEditingController controleur;

    Future<void> ouvrir(WidgetTester t) async {
      lieux = [];
      controleur = TextEditingController();
      addTearDown(controleur.dispose);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChampAdresseLieu(controleur: controleur, longueurMax: 120, onLieu: lieux.add),
        ),
      ));
    }

    testWidgets('choisir une suggestion remplit le champ et donne les coordonnées', (t) async {
      await ouvrir(t);
      await t.enterText(find.byType(TextFormField), 'badala');
      await t.pump();

      await t.tap(find.text('Badalabougou'));
      await t.pump();

      expect(controleur.text, 'Badalabougou');
      expect(lieux.last?.lat, isNotNull);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('modifier le texte après un choix oublie les coordonnées', (t) async {
      await ouvrir(t);
      await t.enterText(find.byType(TextFormField), 'badala');
      await t.pump();
      await t.tap(find.text('Badalabougou'));
      await t.pump();

      await t.enterText(find.byType(TextFormField), 'Badalabougou, rue 12');
      await t.pump();

      expect(lieux.last, isNull);
    });

    testWidgets('au plus 4 suggestions, et aucune pour une saisie inconnue', (t) async {
      await ouvrir(t);
      await t.enterText(find.byType(TextFormField), 'ba');
      await t.pump();
      expect(find.byType(ListTile), findsNWidgets(4));

      await t.enterText(find.byType(TextFormField), 'zzzzzz');
      await t.pump();
      expect(find.byType(ListTile), findsNothing);
    });
  });
}
