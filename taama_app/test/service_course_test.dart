import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/models/service_course.dart';

ServiceCourse _service({
  int id = 1,
  String nom = 'Service',
  bool necessiteClimatisation = false,
  bool disponible = true,
  int? prix = 1000,
}) {
  return ServiceCourse(
    id: id,
    nom: nom,
    description: '',
    typeVehicule: 'BERLINE',
    necessiteClimatisation: necessiteClimatisation,
    disponible: disponible,
    prix: prix,
    etaMinutes: 5,
    placesMax: 4,
    conducteursProches: 1,
  );
}

void main() {
  group('trouverStandardDeRepli', () {
    test('retourne le service non-clim disponible le moins cher parmi plusieurs', () {
      final services = [
        _service(id: 1, nom: 'Berline A', prix: 1500),
        _service(id: 2, nom: 'Berline B', prix: 900),
        _service(id: 3, nom: 'Berline C', prix: 1200),
      ];

      final repli = trouverStandardDeRepli(services);

      expect(repli, isNotNull);
      expect(repli!.id, 2);
      expect(repli.prix, 900);
    });

    test('ignore les services climatisés même moins chers', () {
      final services = [
        _service(id: 1, nom: 'Confort', necessiteClimatisation: true, prix: 500),
        _service(id: 2, nom: 'Standard', necessiteClimatisation: false, prix: 1000),
      ];

      final repli = trouverStandardDeRepli(services);

      expect(repli, isNotNull);
      expect(repli!.id, 2);
    });

    test('ignore les indisponibles même non-climatisés', () {
      final services = [
        _service(id: 1, nom: 'Pas cher mais indispo', disponible: false, prix: 500),
        _service(id: 2, nom: 'Disponible', disponible: true, prix: 1000),
      ];

      final repli = trouverStandardDeRepli(services);

      expect(repli, isNotNull);
      expect(repli!.id, 2);
    });

    test('ignore les services à prix null', () {
      final services = [
        _service(id: 1, nom: 'Prix inconnu', disponible: true, prix: null),
        _service(id: 2, nom: 'Prix connu', disponible: true, prix: 1000),
      ];

      final repli = trouverStandardDeRepli(services);

      expect(repli, isNotNull);
      expect(repli!.id, 2);
    });

    test('retourne null si aucun candidat valide', () {
      final services = [
        _service(id: 1, necessiteClimatisation: true, prix: 500),
        _service(id: 2, disponible: false, prix: 600),
        _service(id: 3, disponible: true, prix: null),
      ];

      final repli = trouverStandardDeRepli(services);

      expect(repli, isNull);
    });

    test('retourne null sur une liste vide', () {
      expect(trouverStandardDeRepli(const []), isNull);
    });
  });

  group('ServiceCourse.fromJson', () {
    test('parse un JSON complet valide correctement', () {
      final service = ServiceCourse.fromJson({
        'id': 42,
        'nom': 'Confort',
        'description': 'Berline climatisée',
        'type_vehicule': 'BERLINE',
        'necessite_climatisation': true,
        'disponible': true,
        'prix': 1200,
        'eta_minutes': 7,
        'places_max': 4,
        'conducteurs_proches': 3,
      });

      expect(service.id, 42);
      expect(service.nom, 'Confort');
      expect(service.description, 'Berline climatisée');
      expect(service.typeVehicule, 'BERLINE');
      expect(service.necessiteClimatisation, true);
      expect(service.disponible, true);
      expect(service.prix, 1200);
      expect(service.etaMinutes, 7);
      expect(service.placesMax, 4);
      expect(service.conducteursProches, 3);
    });

    test('id absent lève FormatException', () {
      expect(
        () => ServiceCourse.fromJson({'nom': 'Sans id'}),
        throwsFormatException,
      );
    });

    test('id null lève FormatException', () {
      expect(
        () => ServiceCourse.fromJson({'id': null, 'nom': 'Id null'}),
        throwsFormatException,
      );
    });

    test('id à 0 lève FormatException', () {
      expect(
        () => ServiceCourse.fromJson({'id': 0, 'nom': 'Id zéro'}),
        throwsFormatException,
      );
    });

    test('id négatif lève FormatException', () {
      expect(
        () => ServiceCourse.fromJson({'id': -1, 'nom': 'Id négatif'}),
        throwsFormatException,
      );
    });

    test('id non-numérique lève FormatException', () {
      expect(
        () => ServiceCourse.fromJson({'id': 'abc', 'nom': 'Id texte'}),
        throwsFormatException,
      );
    });

    test('id fourni en string numérique est accepté (parsing défensif)', () {
      final service = ServiceCourse.fromJson({'id': '7', 'nom': 'Id string'});
      expect(service.id, 7);
    });

    test('prix null et eta_minutes null sont gérés (champs optionnels)', () {
      final service = ServiceCourse.fromJson({
        'id': 1,
        'nom': 'Indisponible',
        'disponible': false,
        'prix': null,
        'eta_minutes': null,
      });

      expect(service.prix, isNull);
      expect(service.etaMinutes, isNull);
      expect(service.disponible, false);
    });

    test('champs texte/bool/int manquants tombent sur leurs défauts sans crash', () {
      final service = ServiceCourse.fromJson({'id': 1});

      expect(service.nom, '');
      expect(service.description, '');
      expect(service.typeVehicule, '');
      expect(service.necessiteClimatisation, false);
      expect(service.disponible, false);
      expect(service.prix, isNull);
      expect(service.etaMinutes, isNull);
      expect(service.placesMax, 0);
      expect(service.conducteursProches, 0);
    });
  });
}
