// Annulation d'une course : l'écran de navigation réagit quand le client annule,
// et le dialogue du chauffeur annonce les conditions du serveur.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/services/annulations_course.dart';
import 'package:taama_conducteur/widgets/widget_annulation.dart';

String _lire(String chemin) => File(chemin).readAsStringSync();

void main() {
  test('le signal d’annulation arrive à tous les écrans qui écoutent', () async {
    final recus = <int>[];
    final abonnement = AnnulationsCourse.flux.listen(recus.add);
    AnnulationsCourse.signaler(42);
    await Future<void>.delayed(Duration.zero);
    await abonnement.cancel();
    expect(recus, [42]);
  });

  group('conditionsAnnulationChauffeur', () {
    test('pas encore acceptée : gratuite', () {
      final c = conditionsAnnulationChauffeur(secondesGratuites: null, penaliteTardive: 500);
      expect(c.gratuite, isTrue);
      expect(c.texte, contains('gratuite'));
    });
    test('dans le délai : minutes restantes, arrondies au-dessus', () {
      final c = conditionsAnnulationChauffeur(secondesGratuites: 61, penaliteTardive: 500);
      expect(c.gratuite, isTrue);
      expect(c.texte, contains('2 min'));
    });
    test('délai dépassé : le montant du serveur', () {
      final c = conditionsAnnulationChauffeur(secondesGratuites: 0, penaliteTardive: 500);
      expect(c.gratuite, isFalse);
      expect(c.texte, contains('500\u202fF'));
    });
    test('mode gratuit : aucun montant, mais elle compte toujours', () {
      final c = conditionsAnnulationChauffeur(secondesGratuites: 0, penaliteTardive: 0);
      expect(c.gratuite, isFalse);
      expect(c.texte, isNot(contains('Pénalité')));
      expect(c.texte, contains('répétées'));
    });
  });

  group('réaction à l’annulation', () {
    final navigation = _lire('lib/screens/navigation_screen.dart');

    test('la navigation écoute le signal et ferme proprement', () {
      expect(navigation, contains('AnnulationsCourse.flux.listen(_surAnnulationClient)'));
      expect(navigation, contains('_abonnementAnnulation?.cancel()'));
      expect(navigation, contains('Le client a annulé cette course.'));
    });

    test('sa propre fin de course n’est pas prise pour une annulation', () {
      final terminer = navigation.substring(navigation.indexOf('Future<void> _terminerCourse'));
      expect(
        terminer.indexOf('_terminaisonEnCours = true'),
        lessThan(terminer.indexOf('ApiService.terminerCourse')),
      );
    });

    test('le push et l’accueil déclenchent le signal', () {
      expect(_lire('lib/services/notification_service.dart'), contains('AnnulationsCourse.signaler'));
      expect(_lire('lib/screens/espace_chauffeur_screen.dart'), contains('AnnulationsCourse.signaler'));
    });
  });

  // Les boutons radio passent par RadioGroup : le choix doit marcher.
  testWidgets('dialogue : « Confirmer » inactif sans motif, puis le motif choisi est renvoyé', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    Map<String, dynamic>? resultat;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => resultat = await afficherDialogueAnnulation(context, secondesGratuites: 60, penaliteTardive: 0, estChauffeur: true),
          child: const Text('ouvrir'),
        ),
      ),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    final confirmer = find.widgetWithText(ElevatedButton, 'Confirmer l\'annulation');
    expect(t.widget<ElevatedButton>(confirmer).onPressed, isNull);
    await t.tap(find.text('Client absent'));
    await t.pump();
    expect(t.widget<ElevatedButton>(confirmer).onPressed, isNotNull);
    await t.tap(confirmer);
    await t.pumpAndSettle();
    expect(resultat, {'motif': 'CLIENT_ABSENT'});
    expect(t.takeException(), isNull);
  });
}
