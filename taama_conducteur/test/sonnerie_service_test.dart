// Sonnerie d'une demande (SonnerieService) : arrêtée pendant le lancement du
// son, elle ne relance ni la vibration en boucle ni l'arrêt automatique.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/services/sonnerie_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sonnerie = SonnerieService.instance;

  tearDown(() async {
    await sonnerie.arreter();
    sonnerie.lecturePourTest = null;
  });

  test('arrêtée pendant le lancement du son : plus de vibration', () async {
    final son = Completer<void>();
    sonnerie.lecturePourTest = () => son.future;
    final demarrage = sonnerie.demarrer();
    await sonnerie.arreter(); // la demande a disparu
    son.complete(); // le son finit de se lancer
    await demarrage;
    expect(sonnerie.enCours, isFalse);
    expect(sonnerie.vibre, isFalse);
  });

  test('sans arrêt : elle sonne et vibre jusqu’à l’arrêt', () async {
    sonnerie.lecturePourTest = () async {};
    await sonnerie.demarrer();
    expect(sonnerie.enCours, isTrue);
    expect(sonnerie.vibre, isTrue);
    await sonnerie.arreter();
    expect(sonnerie.vibre, isFalse);
  });

  test('son impossible : la vibration prévient quand même', () async {
    sonnerie.lecturePourTest = () async => throw Exception('audio occupé');
    await sonnerie.demarrer();
    expect(sonnerie.vibre, isTrue);
  });
}
