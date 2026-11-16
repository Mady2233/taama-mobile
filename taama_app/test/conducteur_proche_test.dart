// Lecture d'une entrée de conducteurs/proches/ (carte d'accueil), réponse du
// serveur depuis la pseudonymisation (identifiant en texte, sans photo,
// position arrondie à 0,001°) comme ancienne (identifiant entier, photo).
// ConducteurProche.depuisJson est le code des builds installés depuis le 31/10
// (identique dans les commits de leurs builds) : ils lisent la nouvelle réponse.
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/screens/home/home_models.dart';

void main() {
  test('nouvelle réponse : pseudonyme en texte, sans photo, position arrondie', () {
    final c = ConducteurProche.depuisJson({
      'id': '3f9a1c0b7e2d4a65',
      'nom_court': 'Seydou K.',
      'type_transport': 'Moto',
      'vehicule': 'Yamaha YBR',
      'note': '4.8',
      'verifie': true,
      'distance_km': 1.1,
      'temps_minutes': 3,
      'lat': 12.649,
      'lng': -8.001,
    });
    expect(c, isNotNull);
    expect(c!.id, '3f9a1c0b7e2d4a65');
    expect(c.urlPhoto, isNull);
    expect(c.position.latitude, 12.649);
    expect(c.position.longitude, -8.001);
    expect(c.note, 4.8);
    expect(c.estMoto, isTrue);
    // Serveur d'avant le 16/11 : jamais le « 5.0 » par défaut en vitrine.
    expect(c.notePublique, isNull);
    expect(c.minutesAvant, 3);
  });

  test('réponse du 16/11 : champs du radar préférés, anciens en repli', () {
    final c = ConducteurProche.depuisJson({
      'id': '3f9a1c0b7e2d4a65',
      'nom_court': 'Seydou K.',
      'nom_affiche': 'Seydou',
      'type_transport': 'Moto',
      'note': '5.0',
      'note_publique': null,
      'temps_minutes': 3,
      'eta_min': 4,
      'lat': 12.649,
      'lng': -8.001,
    });
    expect(c!.nomCourt, 'Seydou');
    expect(c.prenom, 'Seydou');
    expect(c.initiales, 'S');
    expect(c.notePublique, isNull, reason: 'moins de 5 notes : « Nouveau », jamais 5.0');
    expect(c.minutesAvant, 4, reason: 'le temps du radar, pas les 20 km/h à vol d’oiseau');
  });

  test('note publique présente, prénom et initiales', () {
    final c = ConducteurProche.depuisJson({
      'id': 'a1', 'nom_affiche': 'Seydou K.', 'type_transport': 'Moto',
      'note_publique': 4.8, 'eta_min': 2, 'lat': 12.6, 'lng': -8.0,
    });
    expect(c!.notePublique, 4.8);
    expect(c.prenom, 'Seydou');
    expect(c.initiales, 'SK');
    final vide = ConducteurProche.depuisJson({'id': 'a2', 'lat': 12.6, 'lng': -8.0});
    expect(vide!.prenom, 'Chauffeur');
    expect(vide.initiales, '?');
  });

  test('ancienne réponse : identifiant entier, photo, position précise', () {
    final c = ConducteurProche.depuisJson({
      'id': 42,
      'nom_court': 'Awa D.',
      'type_transport': 'Voiture',
      'photo_profil': 'https://pub-exemple.r2.dev/profils/42.jpg',
      'lat': 12.649171,
      'lng': -8.001234,
    });
    expect(c!.id, '42');
    expect(c.urlPhoto, 'https://pub-exemple.r2.dev/profils/42.jpg');
    expect(c.estMoto, isFalse);
  });

  test('champs facultatifs absents ou nuls : aucune exception', () {
    for (final brut in [
      {'id': 'a1', 'lat': 12.6, 'lng': -8.0},
      {'id': 'a1', 'lat': 12.6, 'lng': -8.0, 'nom_court': null, 'vehicule': null, 'note': null,
        'temps_minutes': null, 'photo_profil': null, 'type_transport': null},
    ]) {
      final c = ConducteurProche.depuisJson(brut);
      expect(c, isNotNull);
      expect(c!.nomCourt, '');
      expect(c.note, isNull);
      expect(c.modeleVehicule, isNull);
    }
  });

  test('entrée inexploitable : ignorée (null), jamais d’exception', () {
    for (final brut in <Object?>[
      null,
      'texte',
      {'lat': 12.6, 'lng': -8.0},
      {'id': 'a1', 'lng': -8.0},
      {'id': 'a1', 'lat': 91, 'lng': -8.0},
    ]) {
      expect(ConducteurProche.depuisJson(brut), isNull, reason: '$brut');
    }
  });
}
