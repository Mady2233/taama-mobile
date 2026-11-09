// Aucune couleur hexadécimale en dur dans les écrans de la course : elles
// passent par le thème (lib/theme/taama_theme.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final chemin in const [
    'lib/screens/resultats_recherche_screen.dart',
    'lib/screens/course/suivi_course_screen.dart',
    'lib/screens/verification_identite_screen.dart',
    'lib/widgets/invitation_identite.dart',
  ]) {
    test('pas de couleur en dur : $chemin', () {
      expect(File(chemin).readAsStringSync(), isNot(contains('Color(0x')));
    });
  }
}
