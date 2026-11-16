// Pastilles des chauffeurs proches sur l'accueil : regroupement quand elles
// se toucheraient à l'écran (positions arrondies à ~110 m), fiche au toucher
// sans aucune commande, lisible en 360 × 640 et avec le texte à 130 %.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taama_app/screens/home/home_screen.dart';
import 'package:taama_app/widgets/taama/couche_chauffeurs_accueil.dart';
import 'package:taama_app/widgets/taama/fiche_chauffeurs_proches.dart';

const _bamako = LatLng(12.6392, -8.0029);

ConducteurProche _chauffeur(
  String id, {
  required LatLng position,
  String nom = 'Seydou K.',
  double? note,
  int? minutes,
  bool estMoto = true,
  String? vehicule,
}) =>
    ConducteurProche(
      id: id,
      nomCourt: nom,
      position: position,
      notePublique: note,
      minutesAvant: minutes,
      estMoto: estMoto,
      modeleVehicule: vehicule,
    );

/// Projection plate : 1° = 100 000 px (assez pour comparer des distances).
Offset _ecran(LatLng p) => Offset(p.longitude * 100000, p.latitude * 100000);

void main() {
  group('grouperParEcran', () {
    test('même point à l’écran : une seule pastille, le temps le plus court', () {
      final groupes = grouperParEcran([
        (_chauffeur('a', position: _bamako, minutes: 4), _bamako),
        (_chauffeur('b', position: _bamako, minutes: 2), _bamako),
        (_chauffeur('c', position: const LatLng(12.6500, -8.0029), minutes: 7),
            const LatLng(12.6500, -8.0029)),
      ], _ecran);
      expect(groupes, hasLength(2));
      expect(groupes.first.chauffeurs.map((c) => c.id), ['a', 'b']);
      expect(groupes.first.minutes, 2);
      expect(groupes.last.minutes, 7);
    });

    test('le seuil est en pixels : dézoomer regroupe', () {
      const voisins = LatLng(12.6392, -8.0020); // ~100 m : une case de la grille
      final entrees = [
        (_chauffeur('a', position: _bamako), _bamako),
        (_chauffeur('b', position: voisins), voisins),
      ];
      // Zoom serré : 1° = 100 000 px, 90 px d'écart : deux pastilles.
      expect(grouperParEcran(entrees, _ecran), hasLength(2));
      // Dézoomé (projection divisée par 10) : 9 px, elles se toucheraient.
      expect(grouperParEcran(entrees, (p) => _ecran(p) / 10), hasLength(1));
    });

    test('temps inconnus : pas de temps inventé', () {
      final groupes = grouperParEcran(
        [(_chauffeur('a', position: _bamako), _bamako)],
        _ecran,
      );
      expect(groupes.single.minutes, isNull);
    });
  });

  group('accueil', () {
    Future<void> afficher(WidgetTester tester,
        {required List<ConducteurProche> conducteurs, double echelle = 1.0}) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        builder: (context, enfant) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(echelle)),
          child: enfant!,
        ),
        home: HomeScreen(
          paiementActif: false,
          coucheFond: const SizedBox.shrink(),
          positionClient: _bamako,
          conducteursProches: conducteurs,
          onChercherDestination: () {},
          onSuggestion: (_) {},
          onAjouterAdresse: () {},
          onService: (_) {},
          onReserver: () {},
          onColis: () {},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    final deuxMemePoint = [
      _chauffeur('a', position: _bamako, nom: 'Seydou K.', note: 4.8, minutes: 4, vehicule: 'Yamaha YBR'),
      _chauffeur('b', position: _bamako, nom: 'Awa D.', minutes: 6, estMoto: false),
      // ~330 m au nord : une pastille à part sur l'écran.
      _chauffeur('c', position: const LatLng(12.6422, -8.0029), nom: 'Mady T.', minutes: 2),
    ];

    testWidgets('deux chauffeurs d’une même cellule : une pastille groupée', (tester) async {
      await afficher(tester, conducteurs: deuxMemePoint);
      expect(find.text('2'), findsOneWidget, reason: 'le nombre du groupe');
      expect(find.text('4\u00a0min'), findsOneWidget, reason: 'le plus court du groupe');
      expect(find.text('2\u00a0min'), findsOneWidget, reason: 'la pastille seule (MT)');
      expect(find.text('MT'), findsOneWidget, reason: 'initiales de la pastille seule');
      expect(tester.takeException(), isNull);
    });

    testWidgets('toucher le groupe ouvre la fiche, sans aucune commande', (tester) async {
      await afficher(tester, conducteurs: deuxMemePoint);
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FicheChauffeursProches), findsOneWidget);
      expect(find.text('2 chauffeurs proches'), findsOneWidget);
      expect(find.text('Seydou'), findsOneWidget);
      expect(find.text('Awa'), findsOneWidget);
      expect(find.textContaining('4,8 · Yamaha YBR', findRichText: true), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget, reason: 'une seule note publique');
      expect(find.textContaining('Nouveau'), findsOneWidget,
          reason: 'jamais un 5.0 offert d’office');
      expect(find.textContaining('indique d’abord ta destination'), findsOneWidget);
      expect(find.textContaining('Commander'), findsNothing);
      expect(find.textContaining('Choisir'), findsNothing);
    });

    testWidgets('texte à 130 % : tout tient, rien ne déborde', (tester) async {
      await afficher(tester, conducteurs: deuxMemePoint, echelle: 1.3);
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FicheChauffeursProches), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
