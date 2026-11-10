// Écran de demande entrante en entier, sur un petit téléphone (360 × 640 dp,
// barre de navigation à 3 boutons) et en paysage : les boutons et la
// destination restent visibles sans faire défiler, et le panneau ne couvre
// jamais le titre ni le compte à rebours.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/screens/demande_entrante_screen.dart';

// Offre du client, contre-proposition possible, destination sur deux lignes,
// sans coordonnées (pas de carte) : vérifiée par mes-demandes-assignees.
final _demande = jsonEncode([
  {
    'id': 7,
    'statut': 'chauffeur_trouve',
    'destination': 'Hamdallaye ACI 2000, derrière la station, près du grand marché',
    'type_transport': 'Voiture',
    'prix_estime': 1250,
    'prix_standard': 1450,
    'prix_offert': 1250,
    'client_verifie': true,
    'contre_proposition': {'standard': 1450, 'reference': 1250, 'min': 1000, 'max': 1900, 'pas': 50},
  },
]);

Future<void> _ouvrir(WidgetTester t, {required Size taille, required double basSur}) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = taille * 3;
  t.view.devicePixelRatio = 3;
  t.view.padding = FakeViewPadding(top: 24 * 3, bottom: basSur * 3);
  addTearDown(t.view.reset);
  await http.runWithClient(() async {
    await t.pumpWidget(const MaterialApp(home: EcranDemandeEntrante(demandeId: 7)));
    await t.pump(); // réponse du serveur
    await t.pump(const Duration(seconds: 1)); // entrée du panneau
  }, () => MockClient((_) async => http.Response.bytes(utf8.encode(_demande), 200,
      headers: {'content-type': 'application/json; charset=utf-8'})));
  expect(t.takeException(), isNull);
}

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

void main() {
  testWidgets('petit téléphone : boutons et destination visibles, titre et compte à rebours jamais couverts',
      (t) async {
    await _ouvrir(t, taille: const Size(360, 640), basSur: 48);
    _boutonsVisibles(t, 640.0 - 48);
    _enTeteVisible(t);
    // La destination, sans faire défiler : dans la zone visible des informations.
    final infos = t.getRect(find.ancestor(of: find.text('Destination'), matching: find.byType(SingleChildScrollView)));
    expect(t.getRect(find.textContaining('Hamdallaye')).bottom, lessThanOrEqualTo(infos.bottom));
    await t.pumpWidget(const SizedBox()); // compte à rebours arrêté
  });

  testWidgets('paysage : boutons visibles, compte à rebours jamais couvert', (t) async {
    await _ouvrir(t, taille: const Size(640, 360), basSur: 0);
    _boutonsVisibles(t, 360);
    _enTeteVisible(t);
    await t.pumpWidget(const SizedBox());
  });
}
