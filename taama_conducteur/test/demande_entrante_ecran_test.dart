// Écran de demande entrante en entier, avec un faux serveur :
// - sur un petit téléphone (360 × 640 dp, barre de navigation à 3 boutons) et
//   en paysage : les boutons et la destination restent visibles sans faire
//   défiler, et le panneau ne couvre jamais le titre ni le compte à rebours ;
// - contre-proposition : ce que l'écran annonce selon la réponse du serveur.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/screens/demande_entrante_screen.dart';

/// La demande telle que mes-demandes-assignees la renvoie : contre-proposition
/// possible, destination sur deux lignes, sans coordonnées (pas de carte).
Map<String, dynamic> _demande({String statut = 'chauffeur_trouve', bool offre = true, Map<String, dynamic>? contreOffre}) => {
      'id': 7,
      'statut': statut,
      'destination': 'Hamdallaye ACI 2000, derrière la station, près du grand marché',
      'type_transport': 'Voiture',
      'prix_estime': offre ? 1250 : 1450,
      'prix_standard': 1450,
      if (offre) 'prix_offert': 1250,
      'client_verifie': true,
      'contre_proposition': {'standard': 1450, 'reference': offre ? 1250 : 1450, 'min': 1000, 'max': 1900, 'pas': 50},
      if (contreOffre != null) 'contre_offre': contreOffre,
    };

http.Response _json(Object corps, [int statut = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(corps)), statut, headers: {'content-type': 'application/json; charset=utf-8'});

/// Tout le test tourne avec ce faux serveur : les requêtes lancées plus tard,
/// par un bouton ou un minuteur, aussi.
Future<void> _avecServeur(Future<http.Response> Function(http.Request) serveur, Future<void> Function() corps) =>
    http.runWithClient(corps, () => MockClient(serveur));

Future<void> _ouvrir(WidgetTester t, {required Size taille, required double basSur}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = taille * 3;
  t.view.devicePixelRatio = 3;
  t.view.padding = FakeViewPadding(top: 24 * 3, bottom: basSur * 3);
  addTearDown(t.view.reset);
  await t.pumpWidget(const MaterialApp(home: EcranDemandeEntrante(demandeId: 7)));
  await t.pump(); // réponse du serveur
  await t.pump(const Duration(seconds: 1)); // entrée du panneau
  expect(t.takeException(), isNull);
}

Future<http.Response> _serveurSimple(http.Request _) async => _json([_demande()]);

/// Le titre et l'anneau du compte à rebours sont au-dessus du panneau.
void _enTeteVisible(WidgetTester t) {
  final panneau = t.getRect(find.byKey(const ValueKey('panneau-demande')));
  expect(t.getRect(find.text('Nouvelle course')).bottom, lessThanOrEqualTo(panneau.top));
  final anneau = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_AnneauCompteARebours');
  expect(t.getRect(anneau).bottom, lessThanOrEqualTo(panneau.top));
}

/// Boutons entièrement au-dessus de la barre de navigation.
void _boutonsVisibles(WidgetTester t, double basVisible) {
  expect(t.getRect(find.textContaining('Accepter')).bottom, lessThanOrEqualTo(basVisible));
  expect(t.getRect(find.text('Refuser')).bottom, lessThanOrEqualTo(basVisible));
  expect(t.getRect(find.text('Contre-proposer')).bottom, lessThanOrEqualTo(basVisible));
}

/// « Contre-proposer », + une fois, « Proposer ce prix ».
Future<void> _contreProposer(WidgetTester t) async {
  await t.tap(find.text('Contre-proposer'));
  await t.pump();
  await t.tap(find.byIcon(Icons.add_rounded));
  await t.pump();
  await t.tap(find.text('Proposer ce prix'));
  await t.pump(); // réponse du serveur
}

/// Faux serveur d'une contre-proposition que le client refuse : après la
/// proposition, la demande n'est plus à ce chauffeur.
Future<http.Response> Function(http.Request) _refusDuClient({required bool offre}) {
  var proposee = false;
  return (requete) async {
    if (requete.url.path.endsWith('/proposer-prix/')) {
      proposee = true;
      return _json({'contre_offre': {'secondes_restantes': 45}});
    }
    return _json(proposee ? [] : [_demande(offre: offre)]);
  };
}

void main() {
  testWidgets('petit téléphone : boutons et destination visibles, titre et compte à rebours jamais couverts',
      (t) => _avecServeur(_serveurSimple, () async {
            await _ouvrir(t, taille: const Size(360, 640), basSur: 48);
            _boutonsVisibles(t, 640.0 - 48);
            _enTeteVisible(t);
            // La destination, sans faire défiler : dans la zone visible des informations.
            final infos =
                t.getRect(find.ancestor(of: find.text('Destination'), matching: find.byType(SingleChildScrollView)));
            expect(t.getRect(find.textContaining('Hamdallaye')).bottom, lessThanOrEqualTo(infos.bottom));
            await t.pumpWidget(const SizedBox()); // compte à rebours arrêté
          }));

  testWidgets('paysage : boutons visibles, compte à rebours jamais couvert',
      (t) => _avecServeur(_serveurSimple, () async {
            await _ouvrir(t, taille: const Size(640, 360), basSur: 0);
            _boutonsVisibles(t, 360);
            _enTeteVisible(t);
            await t.pumpWidget(const SizedBox());
          }));

  group('contre-proposition refusée par le client', () {
    for (final (offre, message) in [
      (true, 'Le client garde son offre : la course passe à un autre chauffeur.'),
      (false, 'Le client garde le prix standard : la course passe à un autre chauffeur.'),
    ]) {
      testWidgets(offre ? 'avec une offre : il garde son offre' : 'sans offre : il garde le prix standard',
          (t) => _avecServeur(_refusDuClient(offre: offre), () async {
                await _ouvrir(t, taille: const Size(412, 915), basSur: 0);
                await _contreProposer(t);
                expect(find.text('En attente de la réponse du client'), findsOneWidget);
                await t.pump(const Duration(seconds: 3)); // vérification : la demande est partie
                await t.pump();
                expect(find.text(message), findsOneWidget);
                await t.pumpWidget(const SizedBox());
              }));
    }
  });
}
