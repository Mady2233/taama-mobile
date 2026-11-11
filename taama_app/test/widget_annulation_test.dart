// Dialogue d'annulation d'une réservation (widget_annulation.dart, écran
// « Mes réservations ») : motif obligatoire, puis renvoyé.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/widgets/widget_annulation.dart';

void main() {
  // Les boutons radio passent par RadioGroup : le choix doit marcher.
  testWidgets('dialogue : « Confirmer » inactif sans motif, puis le motif choisi est renvoyé', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    Map<String, dynamic>? resultat;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => resultat = await afficherDialogueAnnulation(context, dateCreation: DateTime.now(), estChauffeur: false),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    final confirmer = find.widgetWithText(ElevatedButton, 'Confirmer l\'annulation');
    expect(t.widget<ElevatedButton>(confirmer).onPressed, isNull);
    await t.tap(find.text('Attente trop longue'));
    await t.pump();
    expect(t.widget<ElevatedButton>(confirmer).onPressed, isNotNull);
    await t.tap(confirmer);
    await t.pumpAndSettle();
    expect(resultat, {'motif': 'ATTENTE_TROP_LONGUE'});
    expect(t.takeException(), isNull);
  });
}
