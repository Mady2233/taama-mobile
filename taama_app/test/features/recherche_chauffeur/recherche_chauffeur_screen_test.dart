import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/features/recherche_chauffeur/chauffeur_proche.dart';
import 'package:taama_app/features/recherche_chauffeur/chauffeurs_proches_repository.dart';
import 'package:taama_app/features/recherche_chauffeur/recherche_chauffeur_screen.dart';

const _bamako = GeoPoint(12.6392, -8.0029);

Future<void> _afficher(
  WidgetTester tester, {
  required ChauffeursProchesRepository repository,
  required Future<void> Function(ChauffeurProche) onChoisi,
}) async {
  // Écran de téléphone d'entrée de gamme (360 × 640), pas la surface de test
  // par défaut (800 × 600).
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: RechercheChauffeurScreen(
      repository: repository,
      positionDepart: _bamako,
      onChauffeurChoisi: onChoisi,
    ),
  ));
  // Le faux dépôt attend Future.delayed(Duration.zero) : sans durée, pump()
  // n'avance pas l'horloge du test et la recherche ne finit jamais.
  await tester.pump(Duration.zero);
  // Le panneau grandit en 250 ms (AnimatedSize) quand la liste remplace le
  // squelette : avant la fin, le bouton est encore sous le bord de l'écran.
  await tester.pump(const Duration(milliseconds: 300));
}

class _DepotEnPanne implements ChauffeursProchesRepository {
  @override
  Future<ResultatRecherche> rechercher({
    required GeoPoint position,
    required int rayonM,
    TypeVehicule? type,
  }) async {
    throw const RechercheChauffeursException('Pas de connexion Internet.');
  }
}

void main() {
  testWidgets('affiche les 8 chauffeurs et choisit le plus proche',
      (tester) async {
    ChauffeurProche? choisi;
    await _afficher(
      tester,
      repository: FauxChauffeursProchesRepository(latence: Duration.zero),
      onChoisi: (c) async {
        choisi = c;
      },
    );

    expect(find.text('8 chauffeurs à proximité'), findsOneWidget);

    await tester.tap(find.text('Choisir Seydou'));
    await tester.pump();
    await tester.pump();
    expect(choisi?.prenom, 'Seydou');
    // Après le choix, l'écran relance la recherche : la laisser finir (aucun
    // minuteur en attente à la fin du test).
    await tester.pump(Duration.zero);
  });

  testWidgets('filtre les voitures', (tester) async {
    await _afficher(
      tester,
      repository: FauxChauffeursProchesRepository(latence: Duration.zero),
      onChoisi: (_) async {},
    );

    await tester.tap(find.textContaining('Voitures'));
    await tester.pump();
    expect(find.text('4 chauffeurs à proximité'), findsOneWidget);
    expect(find.text('Choisir Ibrahim'), findsOneWidget);
  });

  testWidgets('affiche l’erreur et propose de réessayer', (tester) async {
    await _afficher(
      tester,
      repository: _DepotEnPanne(),
      onChoisi: (_) async {},
    );

    expect(find.text('Pas de connexion Internet.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.textContaining('Choisir'), findsNothing);
  });
}
