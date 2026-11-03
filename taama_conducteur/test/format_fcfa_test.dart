// Format unique des montants : « 1 000 F », espaces fines insécables, jamais
// « null » ni « FCFA » à l'écran.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/utils/format.dart';

void main() {
  group('formaterFcfa', () {
    test('espaces fines insécables, y compris avant le F', () {
      expect(formaterFcfa(0), '0 F');
      expect(formaterFcfa(999), '999 F');
      expect(formaterFcfa(1000), '1 000 F');
      expect(formaterFcfa(1000000), '1 000 000 F');
    });

    test('montant négatif', () {
      expect(formaterFcfa(-1500), '-1 500 F');
    });
  });

  group('formaterFcfaApi', () {
    test('entier, décimal ou texte', () {
      expect(formaterFcfaApi(0), '0 F');
      expect(formaterFcfaApi(1500), '1 500 F');
      expect(formaterFcfaApi(1500.0), '1 500 F');
      expect(formaterFcfaApi('1500'), '1 500 F');
      expect(formaterFcfaApi('1500.00'), '1 500 F');
    });

    test('absent ou illisible : null, pour masquer le segment', () {
      for (final valeur in <Object?>[null, '', 'abc', 'null', 'NaN', double.nan, double.infinity]) {
        expect(formaterFcfaApi(valeur), isNull, reason: '$valeur');
      }
    });
  });

  test('plus aucun « FCFA » dans le code de l’app', () {
    final fautifs = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && f.readAsStringSync().contains('FCFA'))
        .map((f) => f.path)
        .toList();
    expect(fautifs, isEmpty);
  });
}
