// Commande à un chauffeur choisi sur la carte : jeton envoyé, refus du
// serveur traduits (le devis reste intact, rien n'est commandé).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_app/services/api_service.dart';

Future<(http.Request?, Object?)> _commander({
  required int code,
  Map<String, Object?> corps = const {},
  String? jeton,
}) async {
  http.Request? envoyee;
  Object? exception;
  await http.runWithClient(() async {
    try {
      await ApiService.creerDemandeInstantanee(
        destination: 'Centre',
        devisId: 12,
        typeServiceId: 2,
        jetonChauffeur: jeton,
      );
    } catch (e) {
      exception = e;
    }
  }, () => MockClient((requete) async {
        envoyee = requete;
        // Comme le serveur (DRF) : application/json, sans charset.
        return http.Response.bytes(utf8.encode(jsonEncode(corps)), code,
            headers: {'content-type': 'application/json'});
      }));
  return (envoyee, exception);
}

Matcher _refus(MotifRefusChoix motif) =>
    isA<ChoixChauffeurException>().having((e) => e.motif, 'motif', motif);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.definirToken('jeton-de-session');
  });
  tearDown(() => ApiService.definirToken(''));

  test('le jeton du chauffeur choisi part avec la demande, seulement s’il y en a un', () async {
    final (avec, _) = await _commander(code: 201, corps: {'id': 7}, jeton: 'jeton-signe');
    expect(jsonDecode(avec!.body)['jeton_chauffeur'], 'jeton-signe');
    final (sans, _) = await _commander(code: 201, corps: {'id': 8});
    expect((jsonDecode(sans!.body) as Map).containsKey('jeton_chauffeur'), isFalse);
  });

  test('410 ou 409 CHAUFFEUR_INDISPONIBLE : choisir un autre chauffeur', () async {
    final (_, expire) = await _commander(
      code: 410, jeton: 'j', corps: {'erreur': 'Ce chauffeur n\'est plus disponible.', 'code': 'CHAUFFEUR_INDISPONIBLE'},
    );
    expect(expire, _refus(MotifRefusChoix.chauffeurIndisponible));
    expect(expire.toString(), 'Ce chauffeur n\'est plus disponible.');
    final (_, pris) = await _commander(code: 409, jeton: 'j', corps: {'code': 'CHAUFFEUR_INDISPONIBLE'});
    expect(pris, _refus(MotifRefusChoix.chauffeurIndisponible));
  });

  test('429 LIMITE_CHOIX_CHAUFFEUR : message du serveur', () async {
    const texte = 'Tu as déjà choisi 6 chauffeurs dans la dernière heure.';
    final (_, e) = await _commander(code: 429, jeton: 'j', corps: {'erreur': texte, 'code': 'LIMITE_CHOIX_CHAUFFEUR'});
    expect(e, _refus(MotifRefusChoix.limiteAtteinte));
    expect(e.toString(), texte);
  });

  test('400 CHOIX_CHAUFFEUR_INDISPONIBLE : fonction coupée', () async {
    final (_, e) = await _commander(code: 400, jeton: 'j', corps: {'code': 'CHOIX_CHAUFFEUR_INDISPONIBLE'});
    expect(e, _refus(MotifRefusChoix.fonctionCoupee));
  });

  test('409 DEMANDE_DEJA_EN_COURS : course en cours, avec ou sans choix', () async {
    for (final jeton in ['j', null]) {
      final (_, e) = await _commander(
        code: 409, jeton: jeton, corps: {'erreur': 'Tu as déjà une course en cours.', 'code': 'DEMANDE_DEJA_EN_COURS'},
      );
      expect(e, isA<DemandeDejaEnCoursException>());
      expect(e.toString(), 'Tu as déjà une course en cours.');
    }
  });

  test('409 DEVIS_EXPIRE : nouveau devis, comme avant', () async {
    final (_, e) = await _commander(
      code: 409, jeton: 'j', corps: {'code': 'DEVIS_EXPIRE', 'nouveau_devis_id': 13, 'nouveau_prix': 1450},
    );
    expect(e, isA<DevisExpireException>().having((d) => d.nouveauDevisId, 'nouveauDevisId', 13));
  });

  test('sans chauffeur choisi, un 410 reste une erreur ordinaire', () async {
    final (_, e) = await _commander(code: 410, corps: {'erreur': 'Gone'});
    expect(e, isNot(isA<ChoixChauffeurException>()));
  });
}
