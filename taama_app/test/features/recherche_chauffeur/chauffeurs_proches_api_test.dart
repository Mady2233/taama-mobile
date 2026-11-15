import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_app/features/recherche_chauffeur/chauffeur_proche.dart';
import 'package:taama_app/features/recherche_chauffeur/chauffeurs_proches_api.dart';
import 'package:taama_app/features/recherche_chauffeur/chauffeurs_proches_repository.dart';
import 'package:taama_app/features/recherche_chauffeur/recherche_chauffeur_controller.dart';
import 'package:taama_app/services/api_service.dart';
import 'package:taama_app/services/version_app.dart';

const _bamako = GeoPoint(12.6392, -8.0029);

Map<String, Object?> _entree({String id = 'a1b2c3d4e5f60718'}) => {
      'id': id,
      'jeton': 'jeton-signe',
      'nom_affiche': 'Seydou K.',
      'type_vehicule': 'moto',
      'modele_vehicule': null,
      'couleur_vehicule': null,
      'note': null,
      'verifie': true,
      'tarif_km': 150,
      'distance_m': 1100,
      'eta_min': 4,
      'lat': 12.648,
      'lng': -7.996,
    };

/// Lance une recherche avec un faux serveur qui répond [reponse] (ou lève
/// [erreur]) ; rend la requête envoyée.
Future<(http.Request?, Object?, ResultatRecherche?)> _rechercher({
  http.Response? reponse,
  Object? erreur,
  TypeVehicule? type,
}) async {
  http.Request? envoyee;
  Object? exception;
  ResultatRecherche? resultat;
  await http.runWithClient(() async {
    try {
      resultat = await const ApiChauffeursProchesRepository().rechercher(
        position: _bamako,
        rayonM: 3000,
        type: type,
      );
    } catch (e) {
      exception = e;
    }
  }, () => MockClient((requete) async {
        envoyee = requete;
        if (erreur != null) throw erreur;
        return reponse!;
      }));
  return (envoyee, exception, resultat);
}

Matcher _erreur({required bool reessayable, bool fonctionCoupee = false, String? message}) =>
    isA<RechercheChauffeursException>()
        .having((e) => e.reessayable, 'reessayable', reessayable)
        .having((e) => e.fonctionCoupee, 'fonctionCoupee', fonctionCoupee)
        .having((e) => e.message, 'message', message ?? anything);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.definirToken('jeton-de-session');
    VersionApp.annoncer(app: 'client', plateforme: 'android', build: 71);
  });
  tearDown(() async {
    VersionApp.oublier();
    await ApiService.definirToken('');
  });

  group('ApiChauffeursProchesRepository', () {
    test('POST, position dans le corps, jamais dans l’adresse ; en-têtes de l’app', () async {
      final (requete, exception, _) = await _rechercher(
        reponse: http.Response(jsonEncode({'rayon_m': 3000, 'chauffeurs': []}), 200),
        type: TypeVehicule.moto,
      );
      expect(exception, isNull);
      expect(requete!.method, 'POST');
      expect(requete.url.path, endsWith('/trajets/chauffeurs/proches/'));
      expect(requete.url.hasQuery, isFalse);
      expect(requete.headers['Authorization'], 'Token jeton-de-session');
      expect(requete.headers['X-Taama-App'], 'client/android/71');
      expect(jsonDecode(requete.body), {
        'lat': 12.6392,
        'lng': -8.0029,
        'rayon': 3000,
        'type': 'moto',
      });
    });

    test('sans type : aucun champ type', () async {
      final (requete, _, _) = await _rechercher(
        reponse: http.Response(jsonEncode({'rayon_m': 3000, 'chauffeurs': []}), 200),
      );
      expect((jsonDecode(requete!.body) as Map).containsKey('type'), isFalse);
    });

    test('lit la réponse réelle : modèle, couleur et note nuls ; entrée invalide ignorée', () async {
      final (_, exception, resultat) = await _rechercher(
        reponse: http.Response.bytes(
          utf8.encode(jsonEncode({
            'rayon_m': 2500,
            'chauffeurs': [_entree(), {'id': 'sans-jeton'}],
          })),
          200,
        ),
      );
      expect(exception, isNull);
      expect(resultat!.rayonM, 2500);
      expect(resultat.chauffeurs, hasLength(1));
      final chauffeur = resultat.chauffeurs.single;
      expect(chauffeur.modeleVehicule, '');
      expect(chauffeur.couleurVehicule, '');
      expect(chauffeur.note, isNull);
      expect(chauffeur.tarifKm, 150);
    });

    test('404 : fonction coupée sur le serveur, jamais de nouvel essai', () async {
      final (_, exception, _) = await _rechercher(
        reponse: http.Response(jsonEncode({'code': 'CHOIX_CHAUFFEUR_INDISPONIBLE'}), 404),
      );
      expect(exception, _erreur(reessayable: false, fonctionCoupee: true));
    });

    test('401 : session fermée, message de l’app, sans nouvel essai', () async {
      final (_, exception, _) = await _rechercher(reponse: http.Response('', 401));
      expect(exception, _erreur(reessayable: false, message: SessionInvalideException.message));
    });

    test('400 : sans nouvel essai', () async {
      final (_, exception, _) = await _rechercher(reponse: http.Response('{}', 400));
      expect(exception, _erreur(reessayable: false));
    });

    test('429 et 5xx : nouvel essai', () async {
      for (final code in [429, 500, 503]) {
        final (_, exception, _) = await _rechercher(reponse: http.Response('', code));
        expect(exception, _erreur(reessayable: true), reason: '$code');
      }
    });

    test('réponse illisible : nouvel essai', () async {
      final (_, exception, _) = await _rechercher(reponse: http.Response('<html>', 200));
      expect(exception, _erreur(reessayable: true, message: 'Réponse invalide du serveur.'));
    });

    test('réseau coupé : nouvel essai', () async {
      final (_, exception, _) = await _rechercher(erreur: http.ClientException('hors ligne'));
      expect(exception, _erreur(reessayable: true, message: 'Pas de connexion Internet.'));
    });
  });

  group('RechercheChauffeurController', () {
    test('transmet le type du service au dépôt et filtre dessus', () async {
      final depot = _DepotEnregistreur();
      final controleur = RechercheChauffeurController(
        repository: depot,
        position: _bamako,
        type: TypeVehicule.voiture,
      );
      addTearDown(controleur.dispose);
      await controleur.rafraichir();
      expect(depot.types, [TypeVehicule.voiture]);
      expect(controleur.filtre, TypeVehicule.voiture);
    });

    test('fonction coupée : signalée, et plus aucun essai', () async {
      final depot = _DepotEnregistreur(
        erreur: const RechercheChauffeursException('coupé', reessayable: false, fonctionCoupee: true),
      );
      final controleur = RechercheChauffeurController(
        repository: depot,
        position: _bamako,
        intervalle: const Duration(milliseconds: 1),
      );
      addTearDown(controleur.dispose);
      controleur.demarrer();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controleur.fonctionCoupee, isTrue);
      expect(depot.types, hasLength(1));
    });
  });
}

class _DepotEnregistreur implements ChauffeursProchesRepository {
  _DepotEnregistreur({this.erreur});

  final RechercheChauffeursException? erreur;
  final types = <TypeVehicule?>[];

  @override
  Future<ResultatRecherche> rechercher({
    required GeoPoint position,
    required int rayonM,
    TypeVehicule? type,
  }) async {
    types.add(type);
    final e = erreur;
    if (e != null) throw e;
    return const ResultatRecherche(chauffeurs: [], rayonM: 3000);
  }
}
