// Feuille de choix du véhicule : tout service avec un devis se commande, avec
// ou sans chauffeur proche ; seuls les services sans devis restent grisés.
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
}) =>
    ServiceCourse(
      id: id,
      nom: nom,
      description: '',
      typeVehicule: 'BERLINE',
      necessiteClimatisation: false,
      disponible: disponible,
      prix: prix,
      etaMinutes: eta,
      placesMax: 4,
      conducteursProches: disponible ? 1 : 0,
      devisId: devisId,
    );

Future<Map<String, dynamic>?> _ouvrir(WidgetTester t, List<ServiceCourse> services) async {
  await t.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  Map<String, dynamic>? resultat;
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          resultat = await afficherChoixVehicule(
            context,
            destination: 'Grand Marché',
            distanceKm: 13.7,
            services: services,
          );
        },
        child: const Text('ouvrir'),
      ),
    ),
  ));
  await t.tap(find.text('ouvrir'));
  await t.pumpAndSettle();
  return resultat;
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
    expect(choix?['devis_id'], 10);
    expect(choix?['type_service'], 1);
    expect(choix?['disponible'], false);
  });

  testWidgets('avec chauffeur : temps d’approche, pas de ligne de recherche', (t) async {
    await _ouvrir(t, [_service(id: 1, nom: 'Moto', disponible: true, prix: 1400, devisId: 10, eta: 4)]);
    expect(find.text('4 min'), findsOneWidget);
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
}
