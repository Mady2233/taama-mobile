import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'chauffeur_proche.dart';
import 'chauffeurs_proches_repository.dart';

/// Implémentation HTTP de `GET /api/chauffeurs/proches/`.
///
/// Si l'app a déjà un client API central (Dio, intercepteurs de jeton…),
/// garder cette classe comme référence de parsing et brancher ce client.
class ApiChauffeursProchesRepository implements ChauffeursProchesRepository {
  ApiChauffeursProchesRepository({
    required this.endpoint,
    required this.enTeteAuthorization,
    http.Client? client,
    this.delai = const Duration(seconds: 8),
  }) : _client = client ?? http.Client() {
    if (kReleaseMode && endpoint.scheme != 'https') {
      throw StateError('HTTPS obligatoire en release : $endpoint');
    }
  }

  /// URL complète, ex. `Uri.parse('${ApiConfig.baseUrl}/api/chauffeurs/proches/')`.
  final Uri endpoint;

  /// Valeur complète de l'en-tête Authorization (ex. « Bearer … »),
  /// ou null si l'utilisateur n'est plus connecté.
  final Future<String?> Function() enTeteAuthorization;

  final Duration delai;
  final http.Client _client;

  static const _maxEntrees = 50;

  @override
  Future<ResultatRecherche> rechercher({
    required GeoPoint position,
    required int rayonM,
  }) async {
    if (!position.estValide) {
      throw const RechercheChauffeursException(
        'Position invalide.',
        reessayable: false,
      );
    }
    final auth = await enTeteAuthorization();
    if (auth == null || auth.isEmpty) {
      throw const RechercheChauffeursException(
        'Session expirée. Reconnectez-vous.',
        reessayable: false,
      );
    }

    final uri = endpoint.replace(queryParameters: {
      'lat': position.lat.toStringAsFixed(5),
      'lng': position.lng.toStringAsFixed(5),
      'rayon': '$rayonM',
    });
    final reponse = await _envoyer(uri, auth);

    switch (reponse.statusCode) {
      case 200:
        return _lire(reponse.bodyBytes, rayonM);
      case 401 || 403:
        throw const RechercheChauffeursException(
          'Session expirée. Reconnectez-vous.',
          reessayable: false,
        );
      case 429:
        throw const RechercheChauffeursException(
          'Trop de demandes. Nouvelle tentative dans un instant.',
        );
      default:
        throw const RechercheChauffeursException(
          'Service momentanément indisponible.',
        );
    }
  }

  /// À appeler si ce dépôt possède son propre client HTTP.
  void fermer() => _client.close();

  Future<http.Response> _envoyer(Uri uri, String auth) async {
    try {
      return await _client.get(uri, headers: {
        'Authorization': auth,
        'Accept': 'application/json',
      }).timeout(delai);
    } on TimeoutException {
      throw const RechercheChauffeursException('Réseau lent. Nouvelle tentative…');
    } on Exception {
      throw const RechercheChauffeursException('Pas de connexion Internet.');
    }
  }

  ResultatRecherche _lire(List<int> octets, int rayonDemande) {
    final corps = _decoder(octets);
    if (corps is! Map) {
      throw const RechercheChauffeursException('Réponse invalide du serveur.');
    }
    final liste = corps['chauffeurs'];
    if (liste is! List) {
      throw const RechercheChauffeursException('Réponse invalide du serveur.');
    }

    final vus = <String>{};
    final chauffeurs = <ChauffeurProche>[];
    for (final entree in liste.take(_maxEntrees)) {
      final chauffeur = ChauffeurProche.depuisJson(entree);
      if (chauffeur != null && vus.add(chauffeur.id)) chauffeurs.add(chauffeur);
    }

    final rayon = corps['rayon_m'];
    return ResultatRecherche(
      chauffeurs: chauffeurs,
      rayonM: rayon is int && rayon > 0 ? rayon : rayonDemande,
    );
  }

  static Object? _decoder(List<int> octets) {
    try {
      return jsonDecode(utf8.decode(octets));
    } on FormatException {
      throw const RechercheChauffeursException('Réponse invalide du serveur.');
    }
  }
}
