import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/features/recherche_chauffeur/chauffeur_proche.dart';
import 'package:taama_app/features/recherche_chauffeur/chauffeurs_proches_repository.dart';
import 'package:taama_app/features/recherche_chauffeur/recherche_chauffeur_screen.dart';

const _bamako = GeoPoint(12.6392, -8.0029);

Future<void> _afficher(
  WidgetTester tester, {
  required ChauffeursProchesRepository repository,
  required Future<IssueChoix> Function(ChauffeurProche) onChoisi,
  TypeVehicule? type,
  int? prix,
  VoidCallback? onPlusProche,
  VoidCallback? onFonctionCoupee,
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
      type: type,
      prix: prix,
      onPlusProche: onPlusProche,
      onFonctionCoupee: onFonctionCoupee,
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
        return IssueChoix.quitte;
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

  testWidgets('service Berline : seulement les voitures, sans filtre à toucher', (tester) async {
    await _afficher(
      tester,
      repository: FauxChauffeursProchesRepository(latence: Duration.zero),
      onChoisi: (_) async => IssueChoix.quitte,
      type: TypeVehicule.voiture,
    );

    expect(find.text('4 chauffeurs à proximité'), findsOneWidget);
    expect(find.textContaining('Motos'), findsNothing);
    expect(find.text('Choisir Ibrahim'), findsOneWidget);
  });

  testWidgets('affiche l’erreur et propose de réessayer', (tester) async {
    await _afficher(
      tester,
      repository: _DepotEnPanne(),
      onChoisi: (_) async => IssueChoix.quitte,
    );

    expect(find.text('Pas de connexion Internet.'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
    expect(find.textContaining('Choisir'), findsNothing);
  });

  testWidgets('« Le plus proche » : là même sans chauffeur, avec le prix', (tester) async {
    var plusProche = 0;
    await _afficher(
      tester,
      repository: _DepotEnPanne(),
      onChoisi: (_) async => IssueChoix.quitte,
      prix: 1450,
      onPlusProche: () => plusProche++,
    );

    final bouton = find.textContaining('Le plus proche');
    expect(bouton, findsOneWidget);
    expect(find.textContaining('450'), findsOneWidget);
    await tester.tap(bouton);
    expect(plusProche, 1);
  });

  testWidgets('sans action câblée, pas de bouton « Le plus proche »', (tester) async {
    await _afficher(
      tester,
      repository: FauxChauffeursProchesRepository(latence: Duration.zero),
      onChoisi: (_) async => IssueChoix.quitte,
    );
    expect(find.textContaining('Le plus proche'), findsNothing);
  });

  testWidgets('plafond atteint : choix bloqué, « Le plus proche » reste', (tester) async {
    var choix = 0;
    await _afficher(
      tester,
      repository: FauxChauffeursProchesRepository(latence: Duration.zero),
      onChoisi: (_) async {
        choix++;
        return IssueChoix.limiteAtteinte;
      },
      onPlusProche: () {},
    );

    await tester.tap(find.text('Choisir Seydou'));
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Choix indisponible pour l’instant'), findsOneWidget);
    await tester.tap(find.text('Choix indisponible pour l’instant'), warnIfMissed: false);
    await tester.pump();
    expect(choix, 1);
    expect(find.textContaining('Le plus proche'), findsOneWidget);
  });

  testWidgets('chauffeur déjà pris : la recherche repart aussitôt', (tester) async {
    final depot = _DepotCompteur();
    await _afficher(
      tester,
      repository: depot,
      onChoisi: (_) async => IssueChoix.autreChauffeur,
    );
    final avant = depot.appels;

    await tester.tap(find.text('Choisir Seydou'));
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(depot.appels, avant + 1);
  });

  testWidgets('fonction coupée sur le serveur : la page est prévenue une fois', (tester) async {
    var coupures = 0;
    await _afficher(
      tester,
      repository: _DepotCoupe(),
      onChoisi: (_) async => IssueChoix.quitte,
      onFonctionCoupee: () => coupures++,
    );
    await tester.pump();
    await tester.pump();
    expect(coupures, 1);
  });
}

class _DepotCompteur implements ChauffeursProchesRepository {
  final _faux = FauxChauffeursProchesRepository(latence: Duration.zero);
  int appels = 0;

  @override
  Future<ResultatRecherche> rechercher({
    required GeoPoint position,
    required int rayonM,
    TypeVehicule? type,
  }) {
    appels++;
    return _faux.rechercher(position: position, rayonM: rayonM, type: type);
  }
}

class _DepotCoupe implements ChauffeursProchesRepository {
  @override
  Future<ResultatRecherche> rechercher({
    required GeoPoint position,
    required int rayonM,
    TypeVehicule? type,
  }) async {
    throw const RechercheChauffeursException(
      'Le choix du chauffeur n’est pas disponible pour le moment.',
      reessayable: false,
      fonctionCoupee: true,
    );
  }
}
