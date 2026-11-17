// Feuille « Choisis ta catégorie » : tout service avec un devis se commande,
// avec ou sans chauffeur proche ; seuls les services sans devis restent
// grisés. Toucher une carte la choisit, « Continuer » valide.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/models/service_course.dart';
import 'package:taama_app/widgets/widget_choix_vehicule.dart';

ServiceCourse _service({
  required int id,
  required String nom,
  required bool disponible,
  int? prix,
  int? devisId,
  int? eta,
  String type = 'BERLINE',
  bool clim = false,
}) =>
    ServiceCourse(
      id: id,
      nom: nom,
      description: '',
      typeVehicule: type,
      necessiteClimatisation: clim,
      disponible: disponible,
      prix: prix,
      etaMinutes: eta,
      placesMax: 4,
      conducteursProches: disponible ? 1 : 0,
      devisId: devisId,
    );

/// Ouvre la feuille ; [choix] reçoit ce qu'elle renvoie en se fermant.
Future<void> _ouvrir(
  WidgetTester t,
  List<ServiceCourse> services, {
  int? duree,
  void Function(Map<String, dynamic>?)? choix,
}) async {
  await t.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final resultat = await afficherChoixVehicule(
            context,
            destination: 'Grand Marché',
            distanceKm: 13.7,
            services: services,
            dureeTrajetMinutes: duree,
            horloge: () => DateTime(2026, 11, 17, 14, 20),
          );
          choix?.call(resultat);
        },
        child: const Text('ouvrir'),
      ),
    ),
  ));
  await t.tap(find.text('ouvrir'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sans chauffeur : prix affiché, ligne de recherche, service commandable', (t) async {
    Map<String, dynamic>? choix;
    await t.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            choix = await afficherChoixVehicule(
              context,
              destination: 'Grand Marché',
              distanceKm: 13.7,
              services: [_service(id: 1, nom: 'Moto', disponible: false, prix: 1400, devisId: 10)],
            );
          },
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();

    expect(find.text('1\u202f400\u202fF'), findsOneWidget);
    expect(find.text('Recherche à la commande'), findsOneWidget);
    expect(find.text('Indisponible'), findsNothing);

    await t.tap(find.text('Moto'));
    await t.pumpAndSettle();
    await t.tap(find.text('Continuer avec Moto'));
    await t.pumpAndSettle();
    expect(choix?['devis_id'], 10);
    expect(choix?['type_service'], 1);
    expect(choix?['disponible'], false);
  });

  testWidgets('avec chauffeur : temps d’approche, pas de ligne de recherche', (t) async {
    await _ouvrir(t, [_service(id: 1, nom: 'Moto', disponible: true, prix: 1400, devisId: 10, eta: 4)]);
    expect(find.text('4\u00a0min d’attente'), findsOneWidget);
    expect(find.text('Recherche à la commande'), findsNothing);
  });

  testWidgets('sans devis : grisé, sans prix, repli proposé au tap', (t) async {
    await _ouvrir(t, [
      _service(id: 1, nom: 'Tricycle', disponible: false),
      _service(id: 2, nom: 'Berline', disponible: false, prix: 2100, devisId: 20),
    ]);
    expect(find.text('Indisponible'), findsOneWidget);
    await t.tap(find.text('Tricycle'));
    await t.pumpAndSettle();
    expect(find.textContaining('n\'est pas encore proposé'), findsOneWidget);
    expect(find.textContaining('Commander Berline à 2\u202f100\u202fF'), findsOneWidget);
  });

  testWidgets('sans devis et sans repli : message, jamais de commande', (t) async {
    await _ouvrir(t, [_service(id: 1, nom: 'Tricycle', disponible: false)]);
    await t.tap(find.text('Tricycle'));
    await t.pumpAndSettle();
    expect(find.text('Ce service n\'est pas encore proposé.'), findsOneWidget);
  });

  testWidgets('heures : arrivée estimée et dépose (attente + trajet), à l’heure fixée', (t) async {
    await _ouvrir(t, [_service(id: 1, nom: 'Moto', disponible: true, prix: 1400, devisId: 10, eta: 4)], duree: 18);
    expect(find.text('Arrivée estimée : 14h38 · 18\u00a0min (13,7\u00a0km)'), findsOneWidget);
    expect(find.text('4\u00a0min d’attente · Dépose à 14h42'), findsOneWidget);
  });

  testWidgets('durée du trajet inconnue : ni arrivée ni dépose inventées', (t) async {
    await _ouvrir(t, [_service(id: 1, nom: 'Moto', disponible: true, prix: 1400, devisId: 10, eta: 4)]);
    expect(find.textContaining('Arrivée estimée'), findsNothing);
    expect(find.textContaining('Dépose'), findsNothing);
    expect(find.text('13,7\u00a0km'), findsOneWidget);
  });

  testWidgets('badges calculés : le moins cher, le plus rapide, climatisé', (t) async {
    await _ouvrir(t, [
      _service(id: 1, nom: 'Moto', disponible: true, prix: 1000, devisId: 10, eta: 6, type: 'MOTO'),
      _service(id: 2, nom: 'Berline', disponible: true, prix: 2000, devisId: 20, eta: 3),
      _service(id: 3, nom: 'Confort', disponible: false, prix: 3000, devisId: 30, clim: true),
    ]);
    Finder dans(String nom, String badge) => find.descendant(
          of: find.ancestor(of: find.text(nom), matching: find.byType(InkWell)),
          matching: find.text(badge),
        );
    expect(dans('Moto', 'Le moins cher'), findsOneWidget);
    expect(dans('Berline', 'Le plus rapide'), findsOneWidget);
    expect(dans('Confort', 'Climatisé'), findsOneWidget);
    expect(find.text('Le moins cher'), findsOneWidget);
    expect(find.text('Le plus rapide'), findsOneWidget);
  });

  testWidgets('un seul service : aucun badge de comparaison', (t) async {
    await _ouvrir(t, [_service(id: 1, nom: 'Moto', disponible: true, prix: 1000, devisId: 10, eta: 6)]);
    expect(find.text('Le moins cher'), findsNothing);
    expect(find.text('Le plus rapide'), findsNothing);
  });

  testWidgets('choisi d’avance : le premier commandable ; toucher en choisit un autre', (t) async {
    Map<String, dynamic>? choix;
    await _ouvrir(t, [
      _service(id: 1, nom: 'Moto', disponible: true, prix: 1000, devisId: 10, eta: 6),
      _service(id: 2, nom: 'Berline', disponible: true, prix: 2000, devisId: 20, eta: 3),
    ], choix: (c) => choix = c);
    expect(find.text('Continuer avec Moto'), findsOneWidget);
    await t.tap(find.text('Berline'));
    await t.pumpAndSettle();
    expect(choix, isNull, reason: 'toucher choisit, ne commande pas');
    await t.tap(find.text('Continuer avec Berline'));
    await t.pumpAndSettle();
    expect(choix?['devis_id'], 20);
  });

  testWidgets('texte à 130 % en 360 px : rien ne déborde', (t) async {
    await t.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      builder: (context, enfant) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: enfant!,
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => afficherChoixVehicule(
            context,
            destination: 'Hôpital Gabriel Touré, Quartier du Fleuve',
            distanceKm: 13.7,
            dureeTrajetMinutes: 35,
            services: [
              _service(id: 1, nom: 'Moto', disponible: true, prix: 1000, devisId: 10, eta: 6, type: 'MOTO'),
              _service(id: 2, nom: 'Berline climatisée', disponible: true, prix: 12500, devisId: 20, eta: 3, clim: true),
            ],
          ),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
