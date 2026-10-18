// ConfigApp (mode gratuit lu sur le serveur) : fail-closed, état clair si le
// serveur est injoignable, jamais de blocage à l'ouverture.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/services/config_app.dart';

http.Client _reponse(int code, String corps) =>
    MockClient((requete) async {
      expect(requete.url.path, '/api/config-app/');
      return http.Response(corps, code, headers: {'content-type': 'application/json'});
    });

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ConfigApp.paiementActif.value = false;
  });

  test('par défaut (jamais confirmé) : mode gratuit', () async {
    await ConfigApp.chargerValeurGardee();
    expect(ConfigApp.paiementActif.value, isFalse);
  });

  test('serveur injoignable : état clair, mode gratuit, aucune exception', () async {
    final client = MockClient((_) async => throw const SocketException('hors réseau'));
    await ConfigApp.rafraichir(client: client);
    expect(ConfigApp.paiementActif.value, isFalse);
  });

  test('délai dépassé : rien ne change', () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    await ConfigApp.rafraichir(client: client).timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
    expect(ConfigApp.paiementActif.value, isFalse);
  });

  test('réponses invalides ignorées (500, JSON illisible, type inattendu)', () async {
    for (final (code, corps) in [
      (500, '{"paiement_actif": true}'),
      (200, 'pas du json'),
      (200, '{"paiement_actif": "oui"}'),
      (200, '[]'),
    ]) {
      await ConfigApp.rafraichir(client: _reponse(code, corps));
      expect(ConfigApp.paiementActif.value, isFalse, reason: '$code $corps');
    }
  });

  test('confirmé par le serveur : actif, et gardé pour le prochain lancement', () async {
    await ConfigApp.rafraichir(client: _reponse(200, '{"paiement_actif": true}'));
    expect(ConfigApp.paiementActif.value, isTrue);

    ConfigApp.paiementActif.value = false;
    await ConfigApp.chargerValeurGardee();
    expect(ConfigApp.paiementActif.value, isTrue);
  });

  test('le serveur repasse en mode gratuit : masqué de nouveau', () async {
    await ConfigApp.rafraichir(client: _reponse(200, '{"paiement_actif": true}'));
    await ConfigApp.rafraichir(client: _reponse(200, '{"paiement_actif": false}'));
    expect(ConfigApp.paiementActif.value, isFalse);
  });
}
