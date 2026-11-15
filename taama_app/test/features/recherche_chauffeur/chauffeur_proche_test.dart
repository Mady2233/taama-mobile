import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/features/recherche_chauffeur/chauffeur_proche.dart';

Map<String, Object?> _valide() => {
      'id': 'a1b2c3d4e5f60718',
      'jeton': 'signe:abc',
      'nom_affiche': 'Seydou K.',
      'type_vehicule': 'moto',
      'modele_vehicule': 'Yamaha YBR',
      'couleur_vehicule': 'Noire',
      'note': 4.8,
      'verifie': true,
      'tarif_km': '150.00', // DecimalField DRF sérialisé en chaîne
      'distance_m': 1100,
      'eta_min': 2,
      'lat': 12.639,
      'lng': -8.003,
    };

void main() {
  group('ChauffeurProche.depuisJson', () {
    test('lit une entrée valide, tarif Decimal en chaîne compris', () {
      final c = ChauffeurProche.depuisJson(_valide())!;
      expect(c.tarifKm, 150);
      expect(c.typeVehicule, TypeVehicule.moto);
      expect(c.initiales, 'SK');
      expect(c.prenom, 'Seydou');
      expect(c.verifie, isTrue);
    });

    test('ignore une entrée sans jeton', () {
      expect(ChauffeurProche.depuisJson(_valide()..remove('jeton')), isNull);
    });

    test('ignore un type de véhicule inconnu', () {
      expect(
        ChauffeurProche.depuisJson({..._valide(), 'type_vehicule': 'camion'}),
        isNull,
      );
    });

    test('ignore des coordonnées hors limites', () {
      expect(ChauffeurProche.depuisJson({..._valide(), 'lat': 123.0}), isNull);
    });

    test('ignore un tarif nul ou négatif', () {
      expect(ChauffeurProche.depuisJson({..._valide(), 'tarif_km': 0}), isNull);
    });

    test('ne descend jamais sous 1 min', () {
      expect(ChauffeurProche.depuisJson({..._valide(), 'eta_min': 0})!.etaMin, 1);
    });

    test('écarte une note hors échelle', () {
      expect(ChauffeurProche.depuisJson({..._valide(), 'note': 9})!.note, isNull);
    });

    test('verifie absent ou non booléen vaut false', () {
      expect(
        ChauffeurProche.depuisJson({..._valide(), 'verifie': 'true'})!.verifie,
        isFalse,
      );
    });

    test('rejette ce qui n’est pas un objet', () {
      expect(ChauffeurProche.depuisJson('texte'), isNull);
      expect(ChauffeurProche.depuisJson(null), isNull);
    });
  });

  group('formatage', () {
    test('distance', () {
      expect(formaterDistance(1100), '1,1 km');
      expect(formaterDistance(640), '640 m');
    });

    test('rayon', () {
      expect(formaterRayon(3000), '3 km');
      expect(formaterRayon(1000), '1 km');
    });

    test('tarif', () {
      expect(formaterTarifKm(150), '150 F/km');
      expect(formaterTarifKm(1500), '1 500 F/km');
    });

    test('note', () {
      expect(formaterNote(4.8), '4,8');
    });
  });
}
