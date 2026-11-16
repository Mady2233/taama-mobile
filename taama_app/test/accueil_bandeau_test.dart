// Bandeau des chauffeurs proches de l'accueil : tutoiement, temps
// d'approche le plus court, jamais de temps inventé, cas sans chauffeur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taama_app/screens/home/home_screen.dart';

const _bamako = LatLng(12.6392, -8.0029);

void main() {
  test('textes du bandeau', () {
    expect(texteProximite(chargement: true, nombre: 3, minutes: 2), 'Recherche de chauffeurs…');
    expect(texteProximite(chargement: false, nombre: 1, minutes: 4), '1 chauffeur proche, environ 4\u00a0min');
    expect(texteProximite(chargement: false, nombre: 2, minutes: 2), '2 chauffeurs proches, environ 2\u00a0min');
    expect(texteProximite(chargement: false, nombre: 2), '2 chauffeurs proches');
    expect(
      texteProximite(chargement: false, nombre: 0),
      'Aucun chauffeur en ligne près de toi pour l’instant. Tu peux commander : on cherche pour toi.',
    );
  });

  Future<void> afficher(WidgetTester tester, List<ConducteurProche> conducteurs, {double echelle = 1}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, enfant) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(echelle)),
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

  testWidgets('le temps le plus court des chauffeurs reçus', (tester) async {
    await afficher(tester, const [
      ConducteurProche(id: 'a', nomCourt: 'Seydou K.', position: _bamako, minutesAvant: 6),
      ConducteurProche(id: 'b', nomCourt: 'Awa D.', position: LatLng(12.66, -8.0029), minutesAvant: 2),
    ]);
    expect(find.text('2 chauffeurs proches, environ 2\u00a0min'), findsOneWidget);
    expect(find.textContaining('vous'), findsNothing);
  });

  testWidgets('aucun chauffeur, texte à 130 % : lisible, sans débordement', (tester) async {
    await afficher(tester, const [], echelle: 1.3);
    expect(find.textContaining('Tu peux commander : on cherche pour toi.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
