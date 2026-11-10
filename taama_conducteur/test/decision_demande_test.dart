// Demande entrante : le prix (offre du client et standard), « Accepter · prix »,
// « Refuser », « Contre-proposer » séparé ; contre-proposition ouverte :
// « Proposer ce prix » actif seulement si le prix a changé, « Annuler » ;
// aucun bouton actif pendant un envoi ; rien ne déborde.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/utils/format.dart';
import 'package:taama_conducteur/widgets/decision_demande.dart';

Future<void> _ouvrir(WidgetTester t, Widget enfant, {double largeur = 393}) async {
  await t.binding.setSurfaceSize(Size(largeur, 700));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: enfant))));
  // Pas de pumpAndSettle : un refus en cours tourne sans fin. 800 ms : le
  // montant a fini de défiler (700 ms).
  await t.pump(const Duration(milliseconds: 800));
}

ActionsDemande _actions(
  List<String> journal, {
  bool contrePossible = true,
  bool modeContre = false,
  bool prixModifie = false,
  bool enTraitement = false,
}) =>
    ActionsDemande(
      prix: 1250,
      contrePossible: contrePossible,
      modeContre: modeContre,
      prixModifie: prixModifie,
      enTraitement: enTraitement,
      envoiEnCours: false,
      onAccepter: () => journal.add('accepter'),
      onRefuser: () => journal.add('refuser'),
      onContreProposer: () => journal.add('contre'),
      onProposer: () => journal.add('proposer'),
      onAnnulerContre: () => journal.add('annuler'),
    );

void main() {
  group('prix', () {
    testWidgets('offre du client : le standard et l’écart', (t) async {
      await _ouvrir(t, const BlocPrixDemande(prix: 1250, prixStandard: 1450, prixOffert: 1250));
      expect(find.text('Le client propose'), findsOneWidget);
      expect(find.text(formaterFcfa(1250)), findsOneWidget);
      expect(find.text('Standard ${formaterFcfa(1450)}'), findsOneWidget);
      expect(find.text('−${formaterFcfa(200)}'), findsOneWidget);
    });

    testWidgets('sans offre : le prix de la course seul', (t) async {
      await _ouvrir(t, const BlocPrixDemande(prix: 1450, prixStandard: 1450, prixOffert: null));
      expect(find.text('Prix de la course'), findsOneWidget);
      expect(find.textContaining('Standard'), findsNothing);
    });

    testWidgets('prix inconnu : « — », jamais inventé', (t) async {
      await _ouvrir(t, const BlocPrixDemande(prix: null));
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('contre-proposition envoyée : son prix, jamais attribué au client', (t) async {
      await _ouvrir(t, const BlocPrixDemande(prix: 1450, prixStandard: 1450, prixOffert: 1250, contreProposition: true));
      expect(find.text('Ta contre-proposition'), findsOneWidget);
      expect(find.text('Le client propose'), findsNothing);
      expect(find.text(formaterFcfa(1450)), findsOneWidget);
      expect(find.text('Le client proposait ${formaterFcfa(1250)}'), findsOneWidget);
      expect(find.text('−${formaterFcfa(200)}'), findsNothing);
    });

    testWidgets('code promo : standard et offre comparés après promo, comme le prix', (t) async {
      // Offre 1 250, standard 1 450, promo 145 : le chauffeur encaisse 1 105.
      await _ouvrir(t, const BlocPrixDemande(prix: 1105, prixStandard: 1450, prixOffert: 1250, reduction: 145));
      expect(find.text('Standard ${formaterFcfa(1305)}'), findsOneWidget);
      expect(find.text('−${formaterFcfa(200)}'), findsOneWidget);
      // Contre-proposition à +100 sur l'offre : 1 205, face à l'offre après promo.
      await _ouvrir(t, const BlocPrixDemande(
          prix: 1205, prixStandard: 1450, prixOffert: 1250, reduction: 145, contreProposition: true));
      expect(find.text('Le client proposait ${formaterFcfa(1105)}'), findsOneWidget);
    });

    testWidgets('contre-proposition sans offre du client : le prix standard en rappel', (t) async {
      await _ouvrir(t, const BlocPrixDemande(prix: 1650, prixStandard: 1450, contreProposition: true));
      expect(find.text('Ta contre-proposition'), findsOneWidget);
      expect(find.text('Standard ${formaterFcfa(1450)}'), findsOneWidget);
    });
  });

  group('vue de départ', () {
    testWidgets('accepter, refuser, contre-proposer', (t) async {
      final journal = <String>[];
      await _ouvrir(t, _actions(journal));
      await t.tap(find.text('Accepter · ${formaterFcfa(1250)}'));
      await t.tap(find.text('Refuser'));
      await t.tap(find.text('Contre-proposer'));
      expect(journal, ['accepter', 'refuser', 'contre']);
    });

    testWidgets('sans limites du serveur : pas de « Contre-proposer »', (t) async {
      await _ouvrir(t, _actions([], contrePossible: false));
      expect(find.text('Contre-proposer'), findsNothing);
      expect(find.text('Refuser'), findsOneWidget);
    });

    testWidgets('pendant un envoi : plus aucun bouton actif', (t) async {
      final journal = <String>[];
      await _ouvrir(t, _actions(journal, enTraitement: true));
      await t.tap(find.textContaining('Accepter'));
      await t.tap(find.text('Contre-proposer'));
      expect(journal, isEmpty);
    });
  });

  group('contre-proposition ouverte', () {
    testWidgets('« Proposer ce prix » inactif tant que le prix n’a pas changé', (t) async {
      final journal = <String>[];
      await _ouvrir(t, _actions(journal, modeContre: true));
      await t.tap(find.text('Proposer ce prix'));
      expect(journal, isEmpty);
      expect(find.textContaining('Accepter'), findsNothing);
    });

    testWidgets('prix changé : proposer ; ou annuler', (t) async {
      final journal = <String>[];
      await _ouvrir(t, _actions(journal, modeContre: true, prixModifie: true));
      await t.tap(find.text('Proposer ce prix'));
      await t.tap(find.text('Annuler'));
      expect(journal, ['proposer', 'annuler']);
    });
  });

  testWidgets('petit écran : rien ne déborde', (t) async {
    await _ouvrir(
      t,
      Column(children: [
        const BlocPrixDemande(prix: 125000, prixStandard: 145000, prixOffert: 125000),
        _actions([]),
      ]),
      largeur: 300,
    );
    expect(t.takeException(), isNull);
  });
}
