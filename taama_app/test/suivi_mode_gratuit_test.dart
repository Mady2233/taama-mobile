// Suivi de course en mode gratuit (paiement dans l'app désactivé, lu sur le
// serveur) : jamais de solde, de portefeuille ni de « Payer » ; le client lit
// « paiement en espèces au chauffeur », et peut terminer sans « payer ».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/screens/course/suivi_course_screen.dart';

Future<void> _suivi(
  WidgetTester t, {
  required StatutCourse statut,
  required bool paiementActif,
  bool dejaNotee = false,
}) async {
  await t.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    home: SuiviCourseScreen(
      statut: statut,
      depart: 'Point de départ',
      arrivee: 'Grand Marché',
      prixFcfa: 1500,
      soldeFcfa: 0,
      paiementActif: paiementActif,
      onRetour: () {},
      onAnnuler: () {},
      onPayer: (_) {},
      dejaNotee: dejaNotee,
      onNoter: (_, __) {},
      onTerminer: () {},
    ),
  ));
  await t.pump();
}

void main() {
  testWidgets('course terminée, mode gratuit : espèces, ni solde ni portefeuille ni Payer',
      (t) async {
    await _suivi(t, statut: StatutCourse.terminee, paiementActif: false);
    expect(find.text('Prix convenu · paiement en espèces au chauffeur'), findsOneWidget);
    expect(find.textContaining('Solde'), findsNothing);
    expect(find.textContaining('portefeuille'), findsNothing);
    expect(find.textContaining('Payer'), findsNothing);
    expect(find.text('J’ai payé en espèces'), findsNothing);
  });

  testWidgets('mode gratuit : « Terminer » après la note, sans paiement', (t) async {
    await _suivi(t, statut: StatutCourse.terminee, paiementActif: false, dejaNotee: true);
    expect(find.text('Terminer'), findsOneWidget);
  });

  testWidgets('pendant la course, mode gratuit : aucun « Solde insuffisant »', (t) async {
    await _suivi(t, statut: StatutCourse.enRoute, paiementActif: false);
    expect(find.textContaining('Solde'), findsNothing);
    expect(find.text('Prix convenu · paiement en espèces au chauffeur'), findsOneWidget);
  });

  testWidgets('mode payant : portefeuille et paiement inchangés', (t) async {
    await _suivi(t, statut: StatutCourse.terminee, paiementActif: true);
    expect(find.text('Prix convenu · portefeuille Taama'), findsOneWidget);
    expect(find.textContaining('Solde insuffisant'), findsWidgets);
    expect(find.text('Terminer'), findsNothing, reason: 'non payée, non notée');
  });
}
