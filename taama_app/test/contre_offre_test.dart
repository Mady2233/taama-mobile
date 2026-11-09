// Prix proposé par le chauffeur : le client voit les deux montants et le temps
// qu'il lui reste, accepte ou refuse ; jamais de bouton actif pendant un envoi,
// ni après le délai ; jamais de prix inventé si le serveur n'en envoie pas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/widgets/carte_contre_offre.dart';

const _offre = ContreOffreClient(
  prixPropose: 1650,
  prixActuel: 1450,
  secondesRestantes: 30,
  minutesApproche: 4,
  note: 4.8,
  categorie: 'Berline',
);

Future<(List<String>,)> _carte(
  WidgetTester t, {
  int secondes = 30,
  bool? reponseEnCours,
}) async {
  final actions = <String>[];
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CarteContreOffre(
        offre: _offre,
        secondesRestantes: secondes,
        reponseEnCours: reponseEnCours,
        onAccepter: () => actions.add('accepter'),
        onRefuser: () => actions.add('refuser'),
      ),
    ),
  ));
  return (actions,);
}

void main() {
  group('lecture du bloc serveur', () {
    test('bloc complet', () {
      final o = ContreOffreClient.depuisJson({
        'prix_propose': 1650,
        'prix_actuel': 1450,
        'secondes_restantes': 28,
        'minutes_approche': 4,
        'note': '4.80',
        'categorie': 'Berline',
      })!;
      expect((o.prixPropose, o.prixActuel, o.secondesRestantes, o.minutesApproche), (1650, 1450, 28, 4));
      expect(o.note, 4.8);
      expect(o.categorie, 'Berline');
    });

    test('bloc absent ou incomplet : rien à afficher', () {
      expect(ContreOffreClient.depuisJson(null), isNull);
      expect(ContreOffreClient.depuisJson({'prix_propose': 1650, 'secondes_restantes': 28}), isNull);
    });

    test('détails facultatifs absents : masqués, jamais « null »', () {
      final o = ContreOffreClient.depuisJson({'prix_propose': 1650, 'prix_actuel': 1450, 'secondes_restantes': 28})!;
      expect((o.minutesApproche, o.note, o.categorie), (null, null, null));
    });
  });

  group('carte', () {
    testWidgets('les deux prix, le délai et les détails', (t) async {
      await _carte(t, secondes: 22);
      expect(find.textContaining('Le chauffeur propose 1 650 F au lieu de 1 450 F'), findsOneWidget);
      expect(find.text('22 s pour répondre'), findsOneWidget);
      expect(find.text('À 4 min de toi · Berline · ★ 4,8'), findsOneWidget);
    });

    testWidgets('accepter et refuser', (t) async {
      final (actions,) = await _carte(t);
      await t.tap(find.text('Accepter'));
      await t.tap(find.text('Refuser'));
      expect(actions, ['accepter', 'refuser']);
    });

    testWidgets('pendant un envoi : plus aucun bouton actif', (t) async {
      final (actions,) = await _carte(t, reponseEnCours: true);
      await t.tap(find.byType(OutlinedButton));
      await t.tap(find.byType(FilledButton));
      expect(actions, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('délai dépassé : message, plus de boutons', (t) async {
      await _carte(t, secondes: 0);
      expect(find.textContaining('Délai dépassé'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });
}
