// « Ma position » sur l'accueil, comme les cartes du téléphone : point bleu,
// gris tant que la position n'est pas confirmée, cercle de précision en
// mètres, cône seulement en mouvement, et carte qui suit le client jusqu'à
// ce qu'il la fasse glisser.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:taama_app/screens/home/home_page.dart' show capDepuis;
import 'package:taama_app/screens/home/home_screen.dart';
import 'package:taama_app/theme/taama_theme.dart';
import 'package:taama_app/widgets/couche_carte_taama.dart';
import 'package:taama_app/widgets/taama/point_position.dart';

const _client = LatLng(12.6392, -8.0029);

Position _position({double vitesse = 0, double cap = 0}) => Position(
      latitude: _client.latitude,
      longitude: _client.longitude,
      timestamp: DateTime(2026, 11, 16),
      accuracy: 12,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: cap,
      headingAccuracy: 0,
      speed: vitesse,
      speedAccuracy: 0,
    );

Color _couleurDuPoint(WidgetTester tester) {
  final point = tester.widget<Container>(find.byKey(const ValueKey('point-position')));
  return (point.decoration! as BoxDecoration).color!;
}

void main() {
  group('capDepuis', () {
    test('en mouvement : le cap du GPS', () {
      expect(capDepuis(_position(vitesse: 4, cap: 90)), 90);
    });
    test('à l’arrêt : pas de cap (celui du GPS ne veut rien dire)', () {
      expect(capDepuis(_position(vitesse: 0.3, cap: 90)), isNull);
    });
    test('cap inconnu (négatif) : pas de cap', () {
      expect(capDepuis(_position(vitesse: 4, cap: -1)), isNull);
    });
  });

  group('PointPosition', () {
    Future<void> afficher(WidgetTester tester, PointPosition point) =>
        tester.pumpWidget(MaterialApp(home: Center(child: point)));

    testWidgets('bleu, sans cône à l’arrêt, « Ma position »', (tester) async {
      await afficher(tester, const PointPosition());
      expect(_couleurDuPoint(tester), TaamaColors.position);
      expect(find.byKey(const ValueKey('cone-direction')), findsNothing);
      expect(find.bySemanticsLabel('Ma position'), findsOneWidget);
    });

    testWidgets('en mouvement : le cône de direction', (tester) async {
      await afficher(tester, const PointPosition(cap: 45));
      expect(find.byKey(const ValueKey('cone-direction')), findsOneWidget);
    });

    testWidgets('position pas encore confirmée : gris, jamais de cône', (tester) async {
      await afficher(tester, const PointPosition(cap: 45, approximatif: true));
      expect(_couleurDuPoint(tester), TaamaColors.positionAncienne);
      expect(find.byKey(const ValueKey('cone-direction')), findsNothing);
      expect(find.bySemanticsLabel('Ma position, approximative'), findsOneWidget);
    });
  });

  group('accueil', () {
    Widget accueil({
      LatLng? position = _client,
      double? precision,
      bool approximative = false,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              paiementActif: false,
              coucheFond: const SizedBox.shrink(),
              positionClient: position,
              precisionPositionM: precision,
              positionApproximative: approximative,
              onChercherDestination: () {},
              onSuggestion: (_) {},
              onAjouterAdresse: () {},
              onService: (_) {},
              onReserver: () {},
              onColis: () {},
              onRecentrerCarte: () async {},
            ),
          ),
        );

    Future<void> afficher(WidgetTester tester, Widget ecran) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ecran);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    List<CircleMarker> cercles(WidgetTester tester) => [
          for (final couche in tester.widgetList<CircleLayer>(find.byType(CircleLayer)))
            ...couche.circles,
        ];

    testWidgets('cercle de précision en mètres autour du point', (tester) async {
      await afficher(tester, accueil(precision: 35));
      final cercle = cercles(tester).single;
      expect(cercle.point, _client);
      expect(cercle.radius, 35);
      expect(cercle.useRadiusInMeter, isTrue);
    });

    testWidgets('pas de cercle : précision inconnue, trop large, ou position pas confirmée',
        (tester) async {
      await afficher(tester, accueil());
      expect(cercles(tester), isEmpty);
      await afficher(tester, accueil(precision: 5000));
      expect(cercles(tester), isEmpty);
      await afficher(tester, accueil(precision: 35, approximative: true));
      expect(cercles(tester), isEmpty);
      expect(_couleurDuPoint(tester), TaamaColors.positionAncienne);
    });

    testWidgets('la carte suit le client, plus après un glissement, de nouveau après « recentrer »',
        (tester) async {
      LatLng centre() => MapCamera.of(tester.element(find.byType(CoucheCarteTaama))).center;
      const unPeuPlusLoin = LatLng(12.6400, -8.0029); // ~90 m au nord

      await afficher(tester, accueil());
      await tester.pumpWidget(accueil(position: unPeuPlusLoin));
      await tester.pump();
      expect(const Distance().as(LengthUnit.Meter, centre(), unPeuPlusLoin), lessThan(1),
          reason: 'suivi actif : la carte suit');

      // Le client fait glisser la carte : elle ne le suit plus.
      await tester.drag(find.byType(CoucheCarteTaama), const Offset(0, 120));
      await tester.pump();
      final apresGlissement = centre();
      await tester.pumpWidget(accueil(position: _client));
      await tester.pump();
      expect(centre(), apresGlissement, reason: 'plus de suivi après un glissement');

      // « Recentrer » : de nouveau sur lui, et de nouveau en suivi.
      await tester.tap(find.byTooltip('Recentrer sur ma position'));
      await tester.pump();
      expect(const Distance().as(LengthUnit.Meter, centre(), _client), lessThan(1));
      await tester.pumpWidget(accueil(position: unPeuPlusLoin));
      await tester.pump();
      expect(const Distance().as(LengthUnit.Meter, centre(), unPeuPlusLoin), lessThan(1));
    });
  });
}
