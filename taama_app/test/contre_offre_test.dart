// Contre-proposition du chauffeur : le client voit son offre, le prix proposé,
// l'écart et le temps qu'il lui reste (45 s), accepte ou refuse en gardant son
// offre ; jamais de bouton actif pendant un envoi, ni après le délai ; jamais
// de prix inventé si le serveur n'en envoie pas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/utils/format.dart';
import 'package:taama_app/widgets/carte_contre_offre.dart';

const _offre = ContreOffreClient(
  prixPropose: 1350,
  prixActuel: 1250,
  secondesRestantes: 45,
  minutesApproche: 4,
  note: 4.8,
  categorie: 'Moto',
  aOffre: true,
  prixStandard: 1450,
  distanceKm: 5.6,
);

Future<List<String>> _carte(
  WidgetTester t, {
  ContreOffreClient offre = _offre,
  int secondes = 45,
  bool? reponseEnCours,
}) async {
  final actions = <String>[];
  await t.binding.setSurfaceSize(const Size(393, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CarteContreOffre(
          offre: offre,
          secondesRestantes: secondes,
          reponseEnCours: reponseEnCours,
          paiement: 'Espèces',
          onAccepter: () => actions.add('accepter'),
          onRefuser: () => actions.add('refuser'),
        ),
      ),
    ),
  ));
  return actions;
}

void main() {
  group('lecture du bloc serveur', () {
    test('bloc complet, avec l’offre du client', () {
      final o = ContreOffreClient.depuisJson({
        'prix_propose': 1350,
        'prix_actuel': 1250,
        'secondes_restantes': 44,
        'minutes_approche': 4,
        'note': '4.80',
        'categorie': 'Moto',
      }, demande: {'prix_offert': 1250, 'prix_standard': 1450, 'distance_km': '5.60'})!;
      expect((o.prixPropose, o.prixActuel, o.secondesRestantes, o.minutesApproche), (1350, 1250, 44, 4));
      expect((o.aOffre, o.prixStandard, o.distanceKm), (true, 1450, 5.6));
      expect((o.note, o.categorie), (4.8, 'Moto'));
    });

    test('avec une promo, le standard n’est pas comparable : masqué', () {
      final o = ContreOffreClient.depuisJson(
        {'prix_propose': 1205, 'prix_actuel': 1105, 'secondes_restantes': 40},
        demande: {'prix_offert': 1250, 'prix_standard': 1450},
      )!;
      expect(o.prixStandard, isNull);
    });

    test('bloc absent ou incomplet : rien à afficher', () {
      expect(ContreOffreClient.depuisJson(null), isNull);
      expect(ContreOffreClient.depuisJson({'prix_propose': 1650, 'secondes_restantes': 28}), isNull);
    });

    test('détails facultatifs absents : masqués, jamais « null »', () {
      final o = ContreOffreClient.depuisJson({'prix_propose': 1650, 'prix_actuel': 1450, 'secondes_restantes': 28})!;
      expect((o.minutesApproche, o.note, o.categorie, o.aOffre, o.prixStandard, o.distanceKm),
          (null, null, null, false, null, null));
    });
  });

  group('carte', () {
    testWidgets('le prix proposé, l’offre, l’écart, le délai et le trajet', (t) async {
      await _carte(t, secondes: 34);
      expect(find.text('Un chauffeur te répond'), findsOneWidget);
      expect(find.text(formaterFcfa(1350)), findsOneWidget);
      expect(find.text('Ton offre ${formaterFcfa(1250)}'), findsOneWidget);
      expect(find.text('+${formaterFcfa(100)}'), findsOneWidget);
      expect(find.text('34 s'), findsOneWidget);
      expect(find.text('5,6 km'), findsOneWidget);
      expect(find.text(formaterFcfa(1450)), findsOneWidget);
      expect(find.text('Espèces'), findsOneWidget);
      expect(find.text('★ 4,8 · à 4 min de toi · Moto'), findsOneWidget);
    });

    testWidgets('accepter, ou refuser en gardant son offre', (t) async {
      final actions = await _carte(t);
      await t.tap(find.text('Accepter ${formaterFcfa(1350)}'));
      await t.tap(find.text('Refuser : garder mon offre à ${formaterFcfa(1250)}'));
      expect(actions, ['accepter', 'refuser']);
    });

    testWidgets('sans offre : « garder le prix »', (t) async {
      await _carte(t, offre: const ContreOffreClient(prixPropose: 1550, prixActuel: 1450, secondesRestantes: 40));
      expect(find.text('Refuser : garder le prix à ${formaterFcfa(1450)}'), findsOneWidget);
      expect(find.text('Prix actuel ${formaterFcfa(1450)}'), findsOneWidget);
    });

    testWidgets('pendant un envoi : plus aucun bouton actif', (t) async {
      final actions = await _carte(t, reponseEnCours: true);
      await t.tap(find.byType(TextButton));
      await t.tap(find.byType(FilledButton));
      expect(actions, isEmpty);
    });

    testWidgets('délai dépassé : message, plus de boutons', (t) async {
      await _carte(t, secondes: 0);
      expect(find.textContaining('Délai dépassé'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('petit écran : rien ne déborde', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CarteContreOffre(
              offre: _offre, secondesRestantes: 30, paiement: 'Portefeuille',
              onAccepter: () {}, onRefuser: () {},
            ),
          ),
        ),
      ));
      expect(t.takeException(), isNull);
    });
  });

  test('45 s affichées pour répondre', () => expect(dureeReponseContreOffreSecondes, 45));
}
