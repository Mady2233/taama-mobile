// Carte de l'accueil : étiquettes « Prénom ★ note · minutes » des chauffeurs
// les plus proches (sans chevauchement), boutons de zoom, et attribution
// OpenStreetMap jamais cachée par le bandeau (obligation de licence).
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taama_app/screens/home/home_screen.dart';
import 'package:taama_app/widgets/couche_carte_taama.dart';
import 'package:taama_app/widgets/taama/couche_chauffeurs_accueil.dart';
import 'package:taama_app/widgets/taama/fiche_chauffeurs_proches.dart';
import 'package:taama_app/widgets/taama/vehicule_vu_dessus.dart';

const _client = LatLng(12.6392, -8.0029);
const _ecran = Size(360, 450);

/// Décalé de [nordM] mètres au nord et [estM] mètres à l'est du client.
LatLng _decale(double nordM, double estM) =>
    LatLng(_client.latitude + nordM / 111320, _client.longitude + estM / 108700);

void main() {
  group('placerEtiquettes', () {
    test('vers le milieu de l’écran : à droite à gauche, à gauche à droite', () {
      final cotes = placerEtiquettes(
        centres: const [Offset(60, 100), Offset(300, 300)],
        largeurs: const [150, 150],
        ecran: _ecran,
      );
      expect(cotes, {0: false, 1: true});
    });

    test('côté préféré occupé par une autre pastille : l’autre côté', () {
      final cotes = placerEtiquettes(
        // Une pastille sans étiquette juste à droite de la première.
        centres: const [Offset(160, 200), Offset(250, 200)],
        largeurs: const [150, null],
        ecran: _ecran,
      );
      expect(cotes, {0: true});
    });

    test('aucun côté libre : pas d’étiquette, jamais un chevauchement', () {
      final cotes = placerEtiquettes(
        centres: const [Offset(180, 200), Offset(90, 200), Offset(270, 200)],
        largeurs: const [150, null, null],
        ecran: _ecran,
      );
      expect(cotes, isEmpty);
    });

    test('deux étiquettes voisines ne se recouvrent pas', () {
      // Même hauteur, côte à côte : la seconde ne peut ni aller à gauche
      // (sur la première), ni à droite (hors de l'écran).
      final cotes = placerEtiquettes(
        centres: const [Offset(40, 200), Offset(300, 210)],
        largeurs: const [200, 200],
        ecran: _ecran,
      );
      expect(cotes, {0: false});
    });

    test('jamais hors de l’écran', () {
      final cotes = placerEtiquettes(
        centres: const [Offset(150, 200)],
        largeurs: const [190],
        ecran: const Size(300, 450),
      );
      expect(cotes, isEmpty);
    });
  });

  group('accueil', () {
    Future<void> afficher(WidgetTester tester,
        {required List<ConducteurProche> conducteurs, double echelle = 1.0}) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        builder: (context, enfant) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(echelle)),
          child: enfant!,
        ),
        home: Scaffold(
          body: HomeScreen(
            paiementActif: false,
            coucheFond: const SizedBox.shrink(),
            positionClient: _client,
            conducteursProches: conducteurs,
            onChercherDestination: () {},
            onSuggestion: (_) {},
            onAjouterAdresse: () {},
            onService: (_) {},
            onReserver: () {},
            onColis: () {},
            onRecentrerCarte: () async {},
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Placés pour que les 3 étiquettes aient leur place même avec la police
    // des tests (Ahem : des lettres plus larges que Manrope).
    final quatre = [
      ConducteurProche(id: 'a', nomCourt: 'Seydou K.', position: _decale(180, -250), notePublique: 4.8, minutesAvant: 2),
      ConducteurProche(id: 'b', nomCourt: 'Awa D.', position: _decale(-170, 190), minutesAvant: 3, estMoto: false),
      ConducteurProche(id: 'c', nomCourt: 'Moussa T.', position: _decale(40, 220), notePublique: 4.9, minutesAvant: 4),
      ConducteurProche(id: 'd', nomCourt: 'Oumar B.', position: _decale(-60, -330), notePublique: 4.6, minutesAvant: 6),
    ];

    testWidgets('les 3 plus proches étiquetés, note publique ou « Nouveau » ; le 4e garde ses minutes',
        (tester) async {
      await afficher(tester, conducteurs: quatre);
      expect(find.textContaining('Seydou', findRichText: true), findsOneWidget);
      expect(find.textContaining('4,8', findRichText: true), findsOneWidget);
      expect(find.textContaining('Awa  Nouveau', findRichText: true), findsOneWidget,
          reason: 'sous 5 notes : « Nouveau », jamais un 5,0 offert');
      expect(find.textContaining('Moussa', findRichText: true), findsOneWidget);
      expect(find.textContaining('Oumar', findRichText: true), findsNothing,
          reason: 'au-delà des 3 plus proches : pas d’étiquette');
      expect(find.text('6 min'), findsOneWidget);
      expect(find.byType(VehiculeVuDessus), findsNWidgets(4), reason: 'un véhicule par chauffeur, les initiales restent dans la fiche');
      expect(tester.takeException(), isNull);
    });

    testWidgets('toucher une étiquette ouvre la fiche du chauffeur', (tester) async {
      await afficher(tester, conducteurs: quatre);
      await tester.tap(find.textContaining('Seydou', findRichText: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(FicheChauffeursProches), findsOneWidget);
      expect(find.text('1 chauffeur proche'), findsOneWidget);
    });

    testWidgets('+ et − changent le zoom d’un cran', (tester) async {
      await afficher(tester, conducteurs: quatre);
      double zoom() => MapCamera.of(tester.element(find.byType(CoucheCarteTaama))).zoom;
      final depart = zoom();
      await tester.tap(find.byTooltip('Zoomer'));
      await tester.pump();
      expect(zoom(), depart + 1);
      await tester.tap(find.byTooltip('Dézoomer'));
      await tester.tap(find.byTooltip('Dézoomer'));
      await tester.pump();
      expect(zoom(), depart - 1);
    });

    for (final echelle in [1.0, 1.3]) {
      testWidgets('texte à ${(echelle * 100).round()} % : l’attribution n’est jamais sous le bandeau',
          (tester) async {
        await afficher(tester, conducteurs: quatre, echelle: echelle);
        final attribution = tester.getRect(find.text(AttributionCarteTaama.texte));
        final bandeau = tester.getRect(find.ancestor(
          of: find.textContaining('4 chauffeurs proches'),
          matching: find.byType(Material),
        ).first);
        expect(attribution.overlaps(bandeau), isFalse);
        expect(attribution.top, greaterThanOrEqualTo(bandeau.bottom));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
