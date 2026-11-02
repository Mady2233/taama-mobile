// Suivi de course (lots FOND + FORME) : temps d'arrivée jamais « 0 min » inventé,
// bandeau quand le suivi temps réel décroche, glissement du marqueur, et
// lecture d'une réponse OSRM en un seul appel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taama_app/screens/course/suivi_course_page.dart';
import 'package:taama_app/screens/course/suivi_course_screen.dart';
import 'package:taama_app/services/routing_service.dart';
import 'package:taama_app/utils/format.dart';
import 'package:taama_app/widgets/taama_map.dart';

const _chauffeur = ChauffeurCourse(nomCourt: 'Mady T.', plaque: 'AB 1234 MD', vehicule: 'Toyota Corolla');

Future<void> _suivi(
  WidgetTester t, {
  StatutCourse statut = StatutCourse.enRoute,
  int? minutes,
  double? distanceKm,
  String? etatSuivi,
  ChauffeurCourse chauffeur = _chauffeur,
  VoidCallback? onPartager,
}) async {
  await t.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    home: SuiviCourseScreen(
      statut: statut,
      chauffeur: chauffeur,
      depart: 'Point de départ',
      arrivee: 'Grand Marché',
      prixFcfa: 1500,
      soldeFcfa: 0,
      minutesAvantArrivee: minutes,
      distanceKm: distanceKm,
      etatSuivi: etatSuivi,
      onRetour: () {},
      onAnnuler: () {},
      onPartager: onPartager,
    ),
  ));
  await t.pump();
}

void main() {
  group('temps d\'arrivée', () {
    testWidgets('inconnu : aucun « min » affiché (plus jamais « 0 min »)', (t) async {
      await _suivi(t);
      expect(find.textContaining('min'), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('connu : minutes et distance du serveur OSRM', (t) async {
      await _suivi(t, minutes: 4, distanceKm: 1.2);
      expect(find.text('4 min', findRichText: true), findsOneWidget);
      expect(find.textContaining('1,2 km'), findsOneWidget);
    });
  });

  group('bandeau d\'état du suivi', () {
    testWidgets('affiché sur la carte quand le suivi décroche', (t) async {
      await _suivi(t, etatSuivi: 'Reconnexion au suivi…');
      expect(find.text('Reconnexion au suivi…'), findsOneWidget);
    });

    testWidgets('absent quand tout va bien', (t) async {
      await _suivi(t);
      expect(find.textContaining('Reconnexion'), findsNothing);
      expect(find.textContaining('Localisation'), findsNothing);
    });

    testWidgets('jamais affiché une fois la course terminée', (t) async {
      await _suivi(t, statut: StatutCourse.terminee, etatSuivi: 'Reconnexion au suivi…');
      expect(find.text('Reconnexion au suivi…'), findsNothing);
    });
  });

  group('carte chauffeur (lot FORME)', () {
    const complet = ChauffeurCourse(
      nomCourt: 'Mady T.',
      plaque: 'ab 1234 md',
      vehicule: 'Toyota Corolla',
      couleurLibelle: 'grise',
      note: 4.9,
      nombreCourses: 120,
    );

    testWidgets('véhicule en toutes lettres, couleur accordée en minuscules', (t) async {
      await _suivi(t, chauffeur: complet);
      expect(find.text('Toyota Corolla grise'), findsOneWidget);
    });

    testWidgets('plaque en évidence, en capitales', (t) async {
      await _suivi(t, chauffeur: complet);
      expect(find.text('AB 1234 MD'), findsOneWidget);
    });

    testWidgets('note et nombre de courses : « 4,9 · 120 courses »', (t) async {
      await _suivi(t, chauffeur: complet);
      expect(find.text('4,9 · 120 courses'), findsOneWidget);
    });

    testWidgets('une seule course : singulier', (t) async {
      await _suivi(t,
          chauffeur: const ChauffeurCourse(nomCourt: 'Mady T.', plaque: 'AB 1', nombreCourses: 1));
      expect(find.text('1 course'), findsOneWidget);
    });

    testWidgets('ni note ni courses : aucune ligne, jamais « null »', (t) async {
      await _suivi(t, chauffeur: const ChauffeurCourse(nomCourt: 'Mady T.', plaque: ''));
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining(RegExp(r'\d+ courses?')), findsNothing);
      expect(find.textContaining('Plaque'), findsNothing);
    });

    testWidgets('repli sur les initiales sans photo', (t) async {
      await _suivi(t, chauffeur: complet);
      expect(find.text('MT'), findsOneWidget);
    });
  });

  group('bouton Partager', () {
    testWidgets('masqué quand aucune action n’est câblée', (t) async {
      await _suivi(t);
      expect(find.bySemanticsLabel('Partager le suivi de ma course'), findsNothing);
      expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
    });
  });

  group('libelleVehicule (miroir de Chauffeur.vehicule_libelle)', () {
    test('marque et modèle identiques : une seule fois, majuscule initiale', () {
      expect(libelleVehicule('corola', 'Corola'), 'Corola');
      expect(libelleVehicule('corola', 'corola'), 'Corola');
    });
    test('marque et modèle distincts : les deux', () {
      expect(libelleVehicule('toyota', 'corolla'), 'Toyota Corolla');
    });
    test('casse voulue par le chauffeur respectée', () {
      expect(libelleVehicule('BMW', 'X5'), 'BMW X5');
    });
    test('un seul champ, ou aucun', () {
      expect(libelleVehicule('', 'Corola'), 'Corola');
      expect(libelleVehicule('  Toyota ', null), 'Toyota');
      expect(libelleVehicule(null, '  '), isNull);
    });
  });

  testWidgets('« Corola bleue » : jamais « corola Corola bleue »', (t) async {
    await _suivi(t,
        chauffeur: ChauffeurCourse(
          nomCourt: 'Mady T.',
          plaque: 'AB 1',
          vehicule: libelleVehicule('corola', 'Corola'),
          couleurLibelle: couleurVehiculeFeminin('BLEU'),
        ));
    expect(find.text('Corola bleue'), findsOneWidget);
  });

  group('couleurVehiculeFeminin', () {
    test('code serveur en capitales : accordé au féminin, minuscules', () {
      expect(couleurVehiculeFeminin('GRIS'), 'grise');
      expect(couleurVehiculeFeminin('BLANC'), 'blanche');
      expect(couleurVehiculeFeminin('Argent'), 'argentée');
    });
    test('AUTRE, vide ou inconnu : null (jamais de couleur devinée)', () {
      expect(couleurVehiculeFeminin('AUTRE'), isNull);
      expect(couleurVehiculeFeminin(''), isNull);
      expect(couleurVehiculeFeminin(null), isNull);
    });
  });

  group('etatSuiviChauffeur', () {
    final maintenant = DateTime(2026, 11, 2, 10);
    String? etat({
      bool demarre = true,
      bool? connecte = true,
      DateTime? derniere,
      bool positionConnue = true,
    }) =>
        etatSuiviChauffeur(
          suiviDemarre: demarre,
          connecte: connecte,
          dernierePositionLe: derniere,
          positionConnue: positionConnue,
          maintenant: maintenant,
          ageMax: const Duration(seconds: 30),
        );

    test('suivi non démarré : rien', () {
      expect(etat(demarre: false, connecte: false), isNull);
    });
    test('WebSocket coupé : reconnexion, même si une position est connue', () {
      expect(etat(connecte: false, derniere: maintenant), 'Reconnexion au suivi…');
    });
    test('connecté mais aucune position encore : localisation', () {
      expect(etat(positionConnue: false), 'Localisation du chauffeur…');
      expect(etat(connecte: null, positionConnue: false), 'Localisation du chauffeur…');
    });
    test('position fraîche : rien', () {
      expect(etat(derniere: maintenant.subtract(const Duration(seconds: 10))), isNull);
    });
    test('position de plus de 30 s : mise à jour en cours', () {
      expect(etat(derniere: maintenant.subtract(const Duration(seconds: 31))),
          'Position en cours de mise à jour…');
    });
  });

  group('glissement du marqueur', () {
    const a = LatLng(12.6392, -8.0029);
    const b = LatLng(12.6402, -8.0019); // ~150 m

    test('à mi-parcours : au milieu, pas un saut', () {
      final m = interpolerPosition(a, b, 0.5);
      expect(m.latitude, closeTo(12.6397, 1e-9));
      expect(m.longitude, closeTo(-8.0024, 1e-9));
    });
    test('début et fin exacts', () {
      expect(interpolerPosition(a, b, 0), a);
      expect(interpolerPosition(a, b, 1), b);
    });
    test('saut de plus de 2 km (GPS aberrant) : directement à destination', () {
      const loin = LatLng(12.70, -8.0029); // ~6,8 km
      expect(interpolerPosition(a, loin, 0.3), loin);
    });
  });

  group('lireItineraire (un seul appel OSRM)', () {
    test('tracé, minutes arrondies au-dessus et km', () {
      final r = RoutingService.lireItineraire('''
        {"code":"Ok","routes":[{"duration":125.0,"distance":1234.0,
          "geometry":{"coordinates":[[-8.0029,12.6392],[-8.0019,12.6402]]}}]}
      ''');
      expect(r, isNotNull);
      expect(r!.minutes, 3); // 125 s -> 2,08 min -> 3
      expect(r.km, closeTo(1.234, 1e-9));
      expect(r.trace.first, const LatLng(12.6392, -8.0029)); // [lng, lat] inversé
    });
    test('trajet nul : minimum 1 min, jamais 0', () {
      final r = RoutingService.lireItineraire('''
        {"code":"Ok","routes":[{"duration":0,"distance":0,
          "geometry":{"coordinates":[[-8.0,12.6],[-8.0,12.6]]}}]}
      ''');
      expect(r!.minutes, 1);
    });
    test('réponse inexploitable : null (aucun temps inventé)', () {
      expect(RoutingService.lireItineraire('{"code":"NoRoute","routes":[]}'), isNull);
      expect(RoutingService.lireItineraire('pas du json'), isNull);
      expect(RoutingService.lireItineraire('{"code":"Ok","routes":[{"duration":60}]}'), isNull);
    });
  });
}
