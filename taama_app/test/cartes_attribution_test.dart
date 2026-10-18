import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Attribution OSM/CARTO obligatoire (ODbL, conditions CARTO) et couche de
/// quartiers sur CHAQUE carte : une FlutterMap ajoutée sans elles fait
/// échouer ce test. Fichier identique dans taama_app et taama_conducteur.
void main() {
  test('chaque FlutterMap a AttributionCarteTaama et CoucheCarteTaama', () {
    final fautifs = <String>[];
    var cartesVues = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final source = f.readAsStringSync();
      final cartes = 'FlutterMap('.allMatches(source).length;
      if (cartes == 0) continue;
      cartesVues += cartes;
      final attributions = 'AttributionCarteTaama('.allMatches(source).length;
      final couches = 'CoucheCarteTaama('.allMatches(source).length;
      if (attributions < cartes || couches < cartes) {
        fautifs.add('${f.path} : $cartes carte(s), $attributions attribution(s), '
            '$couches couche(s)');
      }
    }
    // Garde-fou : un test qui ne trouve aucune carte ne prouve rien.
    expect(cartesVues, greaterThan(0));
    expect(fautifs, isEmpty, reason: fautifs.join('\n'));
  });
}
