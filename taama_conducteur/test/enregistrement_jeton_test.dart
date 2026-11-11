// Enregistrement du jeton de notification (EnregistrementJeton) : réponse
// vérifiée, nouveaux essais à délais croissants, arrêt sur réponse
// définitive, 426 → mise à jour proposée, un seul envoi à la fois.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/services/api_service.dart';
import 'package:taama_conducteur/services/enregistrement_jeton.dart';
import 'package:taama_conducteur/services/version_app.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.definirToken('session-essai');
    EnregistrementJeton.reinitialiser();
    EnregistrementJeton.delais = const [Duration(milliseconds: 1), Duration(milliseconds: 2),
        Duration(milliseconds: 3), Duration(milliseconds: 4)];
    VersionApp.surMiseAJourRequise = null;
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.chargerTokenPersiste();
    EnregistrementJeton.reinitialiser();
  });

  /// Le serveur répond [codes] dans l'ordre (null : réseau coupé), puis 200.
  Future<List<String>> envoyer(List<int?> codes, Future<void> Function() corps) async {
    final jetons = <String>[];
    var n = 0;
    await http.runWithClient(corps, () => MockClient((requete) async {
          jetons.add((requete.body.contains('"token"') ? requete.body : ''));
          final code = n < codes.length ? codes[n] : 200;
          n++;
          if (code == null) throw http.ClientException('Réseau coupé');
          return http.Response(code == 426 ? '{"code": "MISE_A_JOUR_REQUISE"}' : '{}', code);
        }));
    return jetons;
  }

  test('les délais par défaut sont croissants (5 essais au plus)', () {
    const d = EnregistrementJeton.delaisParDefaut;
    expect(d.length, 4);
    for (var i = 1; i < d.length; i++) {
      expect(d[i] > d[i - 1], isTrue);
    }
  });

  test('200 : enregistré du premier coup', () async {
    final envois = await envoyer([200], () => EnregistrementJeton.enregistrer('jeton-a'));
    expect(envois.length, 1);
    expect(EnregistrementJeton.derniereIssue, IssueJeton.enregistre);
  });

  test('serveur indisponible puis rétabli : nouveaux essais jusqu’au succès', () async {
    final envois = await envoyer([503, null, 429, 200], () => EnregistrementJeton.enregistrer('jeton-a'));
    expect(envois.length, 4);
    expect(EnregistrementJeton.derniereIssue, IssueJeton.enregistre);
  });

  test('réseau toujours coupé : cinq essais, puis abandon (jamais sans fin)', () async {
    final envois = await envoyer([null, null, null, null, null, null, null], () => EnregistrementJeton.enregistrer('jeton-a'));
    expect(envois.length, 5);
    expect(EnregistrementJeton.derniereIssue, IssueJeton.abandonne);
  });

  test('refus définitif (401) : un seul essai', () async {
    final envois = await envoyer([401], () => EnregistrementJeton.enregistrer('jeton-a'));
    expect(envois.length, 1);
    expect(EnregistrementJeton.derniereIssue, IssueJeton.refuse);
  });

  test('426 : un seul essai, la mise à jour de l’app est proposée', () async {
    var miseAJourProposee = 0;
    VersionApp.surMiseAJourRequise = (_) => miseAJourProposee++;
    final envois = await envoyer([426], () => EnregistrementJeton.enregistrer('jeton-a'));
    expect(envois.length, 1);
    expect(EnregistrementJeton.derniereIssue, IssueJeton.miseAJourRequise);
    expect(miseAJourProposee, 1);
  });

  test('sans session ouverte ni jeton : rien n’est envoyé', () async {
    expect(await envoyer([], () => EnregistrementJeton.enregistrer(null)), isEmpty);
    SharedPreferences.setMockInitialValues({});
    await ApiService.chargerTokenPersiste();
    expect(await envoyer([], () => EnregistrementJeton.enregistrer('jeton-a')), isEmpty);
  });

  test('un seul envoi à la fois : le jeton le plus récent est envoyé ensuite', () async {
    final envois = await envoyer([503, 200, 200], () async {
      final premier = EnregistrementJeton.enregistrer('jeton-a');
      unawaited(EnregistrementJeton.enregistrer('jeton-b'));
      unawaited(EnregistrementJeton.enregistrer('jeton-c'));
      await premier;
    });
    expect(envois.length, 3); // a (503), a (200), puis c — b jamais envoyé
    expect(envois.first, contains('jeton-a'));
    expect(envois.last, contains('jeton-c'));
    expect(envois.any((corps) => corps.contains('jeton-b')), isFalse);
  });
}
