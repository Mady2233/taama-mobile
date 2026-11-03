// Le client n'est « à bord » que si le chauffeur le déclare : la proximité reste
// une suggestion. Sinon, un chauffeur qui passe près du client lui couperait le
// suivi et l'annulation, sans retour en arrière possible.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/screens/navigation_screen.dart';

String _corps(String source, String debut, String fin) =>
    source.substring(source.indexOf(debut), source.indexOf(fin));

void main() {
  group('procheDuPointDePriseEnCharge', () {
    test('s’active à 100 m, pas avant', () {
      expect(procheDuPointDePriseEnCharge(distanceM: 100, dejaProche: false), isTrue);
      expect(procheDuPointDePriseEnCharge(distanceM: 101, dejaProche: false), isFalse);
    });
    test('une fois proche, le reste jusqu’à 150 m : pas de clignotement', () {
      expect(procheDuPointDePriseEnCharge(distanceM: 120, dejaProche: true), isTrue);
      expect(procheDuPointDePriseEnCharge(distanceM: 150, dejaProche: true), isTrue);
      expect(procheDuPointDePriseEnCharge(distanceM: 151, dejaProche: true), isFalse);
    });
  });

  group('le passage en « Course » exige le chauffeur', () {
    final source = File('lib/screens/navigation_screen.dart').readAsStringSync();
    final verifier = _corps(source, 'Future<void> _verifierArrivee', 'Future<void> _demarrerJambeVersDestination');

    test('la détection n’appelle jamais le serveur ni la 2e jambe', () {
      expect(verifier, isNot(contains('marquerClientABord')));
      expect(verifier, isNot(contains('_demarrerJambeVersDestination')));
    });

    test('seul le bouton mène à la 2e jambe, après confirmation', () {
      final appels = RegExp(r'_demarrerJambeVersDestination\(\);').allMatches(source).length;
      expect(appels, 1);
      final bouton = _corps(source, 'Future<void> _clientABordManuel', 'Future<bool?> _confirmer');
      expect(bouton.indexOf('_confirmer('), greaterThan(-1));
      expect(bouton.indexOf('_confirmer('), lessThan(bouton.indexOf('_demarrerJambeVersDestination();')));
    });

    test('échec du serveur : on ne passe pas en « Course » sans relire le statut', () {
      final jambe = _corps(source, 'Future<void> _demarrerJambeVersDestination', 'Future<bool> _clientDejaABordCoteServeur');
      final relecture = jambe.indexOf('_clientDejaABordCoteServeur()');
      final bascule = jambe.indexOf('_jambeVersDestination = true');
      expect(relecture, greaterThan(-1));
      expect(relecture, lessThan(bascule));
    });

    test('l’arrivée à destination garde sa confirmation', () {
      expect(verifier, contains('_proposerFinDeCourse()'));
    });
  });
}
