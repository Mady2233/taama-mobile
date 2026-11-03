// Planification masquée : rien n'active une course planifiée côté serveur, l'app
// ne propose donc pas de réserver à l'avance (jamais de fausse confirmation).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/screens/services_screen.dart';

void main() {
  testWidgets('écran Services : « Réserver » reste, « Planifier » a disparu', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(home: EcranServices()));
    await t.pump();

    expect(find.text('Réserver'), findsOneWidget);
    expect(find.text('Planifier'), findsNothing);
    expect(find.textContaining('à l\'avance'), findsNothing);
  });

  test('écran de résultats : aucune option de planification', () {
    final source = File('lib/screens/resultats_recherche_screen.dart').readAsStringSync();
    expect(source.toLowerCase(), isNot(contains('planifi')));
  });
}
