// Annulation par le client : motif obligatoire, conditions lues sur le serveur et
// jamais de pénalité annoncée à tort.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/widgets/dialogue_annulation_course.dart';

Future<List<String?>> _ouvrir(
  WidgetTester t, {
  int? secondesGratuites = 0,
  int penaliteTardive = 200,
}) async {
  await t.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final resultats = <String?>[];
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          resultats.add(await afficherDialogueAnnulationCourse(
            context,
            secondesGratuites: secondesGratuites,
            penaliteTardive: penaliteTardive,
          ));
        },
        child: const Text('ouvrir'),
      ),
    ),
  ));
  await t.tap(find.text('ouvrir'));
  await t.pumpAndSettle();
  return resultats;
}

void main() {
  group('conditionsAnnulation', () {
    String? texte({int? secondes = 0, int penalite = 200, String? motif}) => conditionsAnnulation(
          secondesGratuites: secondes,
          penaliteTardive: penalite,
          motif: motif,
        );

    test('personne n’a encore accepté : gratuite', () {
      expect(texte(secondes: null), 'Annulation gratuite.');
    });
    test('dans le délai : minutes restantes, arrondies au-dessus', () {
      expect(texte(secondes: 180), 'Annulation gratuite encore 3 min.');
      expect(texte(secondes: 61), 'Annulation gratuite encore 2 min.');
      expect(texte(secondes: 1), 'Annulation gratuite encore 1 min.');
    });
    test('délai dépassé : le montant du serveur', () {
      expect(texte(), contains('200\u202fF'));
      expect(texte(penalite: 350), contains('350\u202fF'));
    });
    test('délai dépassé, chauffeur en cause : gratuite', () {
      expect(texte(motif: 'CONDUCTEUR_NE_VIENT_PAS'), contains('gratuite'));
      expect(texte(motif: 'CONDUCTEUR_INJOIGNABLE'), contains('gratuite'));
      expect(texte(motif: 'PLUS_BESOIN'), contains('200\u202fF'));
    });
    test('mode gratuit : aucune pénalité annoncée', () {
      expect(texte(penalite: 0), isNull);
      expect(texte(penalite: 0, motif: 'PLUS_BESOIN'), isNull);
    });
  });

  test('motifs alignés sur le serveur, tous proposés', () {
    expect(motifsAnnulationClient.keys.toSet(), {
      'ATTENTE_TROP_LONGUE', 'CONDUCTEUR_INJOIGNABLE', 'ERREUR_ADRESSE', 'PLUS_BESOIN',
      'PRIX_TROP_ELEVE', 'CONDUCTEUR_NE_VIENT_PAS', 'AUTRE',
    });
    expect(motifsSansPenalite.every(motifsAnnulationClient.containsKey), isTrue);
  });

  group('dialogue', () {
    TextButton bouton(WidgetTester t) => t.widget<TextButton>(
          find.widgetWithText(TextButton, 'Annuler la course'),
        );

    testWidgets('impossible de confirmer sans motif', (t) async {
      await _ouvrir(t);
      expect(bouton(t).onPressed, isNull);
    });

    testWidgets('le motif choisi est renvoyé', (t) async {
      final resultats = await _ouvrir(t);
      await t.tap(find.text('Attente trop longue'));
      await t.pump();
      await t.tap(find.widgetWithText(TextButton, 'Annuler la course'));
      await t.pumpAndSettle();
      expect(resultats.single, 'ATTENTE_TROP_LONGUE');
    });

    testWidgets('garder la course : aucun motif', (t) async {
      final resultats = await _ouvrir(t);
      await t.tap(find.text('Garder la course'));
      await t.pumpAndSettle();
      expect(resultats.single, isNull);
    });

    testWidgets('le texte suit le motif choisi', (t) async {
      await _ouvrir(t);
      expect(find.textContaining('200\u202fF'), findsOneWidget);
      await t.tap(find.text('Le chauffeur ne vient pas'));
      await t.pump();
      expect(find.textContaining('200\u202fF'), findsNothing);
      expect(find.textContaining('le chauffeur est en cause'), findsOneWidget);
    });

    testWidgets('mode gratuit : aucune mention de pénalité', (t) async {
      await _ouvrir(t, penaliteTardive: 0);
      expect(find.textContaining('pénalité'), findsNothing);
    });
  });
}
