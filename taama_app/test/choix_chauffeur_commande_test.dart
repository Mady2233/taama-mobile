// Choix du chauffeur dans la commande : quels services, et les deux feuilles
// qui le proposent (« Ton offre », « Ton chauffeur »).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/features/recherche_chauffeur/chauffeur_proche.dart';
import 'package:taama_app/models/service_course.dart';
import 'package:taama_app/screens/resultats_recherche_screen.dart';
import 'package:taama_app/theme/taama_theme.dart';
import 'package:taama_app/widgets/choix_mode_chauffeur.dart';
import 'package:taama_app/widgets/choix_offre.dart';

ServiceCourse _service(String type, {bool clim = false}) => ServiceCourse(
      id: 1,
      nom: type,
      description: '',
      typeVehicule: type,
      necessiteClimatisation: clim,
      disponible: true,
      prix: 1450,
      etaMinutes: 4,
      placesMax: 1,
      conducteursProches: 2,
    );

Future<void> _afficher(WidgetTester tester, Widget feuille) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: TaamaTheme.light(),
    home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: feuille)),
  ));
}

void main() {
  test('choix possible pour Moto et Berline, jamais pour Confort, 4x4, tricycle', () {
    expect(typeRadarPourService(_service('MOTO')), TypeVehicule.moto);
    expect(typeRadarPourService(_service('BERLINE')), TypeVehicule.voiture);
    expect(typeRadarPourService(_service('BERLINE', clim: true)), isNull);
    expect(typeRadarPourService(_service('4X4')), isNull);
    expect(typeRadarPourService(_service('TRICYCLE')), isNull);
  });

  const limites = OffreLimites(standard: 1450, min: 1200, max: 1700, pas: 100);

  testWidgets('« Ton offre » : « Choisir mon chauffeur » seulement si possible', (tester) async {
    await _afficher(tester, FeuilleOffre(nomService: 'Moto', limites: limites, onCommander: (_) {}));
    expect(find.text('Choisir mon chauffeur'), findsNothing);
  });

  testWidgets('« Ton offre » : choisir son chauffeur au prix choisi', (tester) async {
    int? choisi;
    await _afficher(
      tester,
      FeuilleOffre(
        nomService: 'Moto',
        limites: limites,
        onCommander: (_) {},
        onChoisirChauffeur: (prix) => choisi = prix,
      ),
    );
    await tester.tap(find.text('Choisir mon chauffeur'));
    expect(choisi, 1450);
  });

  testWidgets('« Ton chauffeur » : le plus proche ou le choisir, même prix', (tester) async {
    final choix = <bool>[];
    await _afficher(tester, FeuilleModeChauffeur(prix: 1450, onChoix: choix.add));
    expect(find.text('Le même prix dans les deux cas.'), findsOneWidget);
    await tester.tap(find.textContaining('Le plus proche'));
    await tester.tap(find.text('Choisir mon chauffeur'));
    expect(choix, [false, true]);
  });
}
