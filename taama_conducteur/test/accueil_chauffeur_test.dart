// Accueil chauffeur (build 74) : gains du jour lus dans « Mes courses »,
// véhicule vu de dessus (voiture ou moto, tourné vers le cap).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taama_conducteur/screens/espace_chauffeur_screen.dart';
import 'package:taama_conducteur/widgets/vehicule_vu_dessus.dart';

void main() {
  group('gainsDuJour', () {
    final maintenant = DateTime(2026, 11, 17, 18, 30);

    test('le jour de maintenant : ses courses et son total', () {
      final g = gainsDuJour({
        'jours': {
          '2026-11-17': {'courses': 7, 'total': 9800},
          '2026-11-16': {'courses': 3, 'total': 4200},
        },
      }, maintenant);
      expect(g.courses, 7);
      expect(g.total, 9800);
    });

    test('aucune course aujourd’hui : 0, jamais le total d’un autre jour', () {
      final g = gainsDuJour({
        'jours': {'2026-11-16': {'courses': 3, 'total': 4200}},
      }, maintenant);
      expect(g.courses, 0);
      expect(g.total, 0);
    });

    test('réponse sans jours ou mal formée : 0, jamais d’erreur', () {
      expect(gainsDuJour({}, maintenant), (courses: 0, total: 0));
      expect(gainsDuJour({'jours': {'2026-11-17': 'x'}}, maintenant), (courses: 0, total: 0));
    });
  });

  group('VehiculeVuDessus', () {
    Future<void> afficher(WidgetTester t, Widget w) =>
        t.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: Center(child: w)));

    testWidgets('tourné vers le cap, à la taille demandée', (t) async {
      await afficher(t, const VehiculeVuDessus(estMoto: true, cap: 1.2, taille: 40));
      final rotation = t.widget<Transform>(
          find.descendant(of: find.byType(VehiculeVuDessus), matching: find.byType(Transform)));
      expect(rotation.transform.getRotation().entry(1, 0), closeTo(0.932, 0.001), reason: 'sin(1,2)');
      expect(t.getSize(find.byType(VehiculeVuDessus)), const Size(40, 40));
    });

    test('capEntre : vers le nord, 0 ; vers l’est, π/2', () {
      expect(capEntre(const LatLng(12.6, -8.0), const LatLng(12.7, -8.0)), closeTo(0, 1e-9));
      expect(capEntre(const LatLng(12.6, -8.0), const LatLng(12.6, -7.9)), closeTo(1.5708, 0.001));
    });

    test('capInitial : stable pour un même identifiant, dans [0, 2π[', () {
      expect(capInitial('abc'), capInitial('abc'));
      expect(capInitial('abc'), inInclusiveRange(0, 6.2832));
    });
  });
}
