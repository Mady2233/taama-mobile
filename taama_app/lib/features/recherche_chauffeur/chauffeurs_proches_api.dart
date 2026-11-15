import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/api_service.dart';
import 'chauffeur_proche.dart';
import 'chauffeurs_proches_repository.dart';

/// Dépôt du radar sur le client API central : `POST /api/trajets/chauffeurs/proches/`
/// par [ApiService.chauffeursProchesRadar] (jeton de session, version de
/// l'app, fin de session sur 401, écran de mise à jour sur 426). Ici :
/// seulement la traduction des codes et la lecture de la réponse.
class ApiChauffeursProchesRepository implements ChauffeursProchesRepository {
  const ApiChauffeursProchesRepository();

  @override
  Future<ResultatRecherche> rechercher({
    required GeoPoint position,
    required int rayonM,
    TypeVehicule? type,
  }) async {
    if (!position.estValide) {
      throw const RechercheChauffeursException(
        'Position invalide.',
        reessayable: false,
      );
    }

    final http.Response reponse;
    try {
      reponse = await ApiService.chauffeursProchesRadar(
        lat: position.lat,
        lng: position.lng,
        rayonM: rayonM,
        type: type?.code,
      );
    } on SessionInvalideException {
      throw const RechercheChauffeursException(
        SessionInvalideException.message,
        reessayable: false,
      );
    } on TimeoutException {
      throw const RechercheChauffeursException('Réseau lent. Nouvelle tentative…');
    } on Exception {
      throw const RechercheChauffeursException('Pas de connexion Internet.');
    }

    switch (reponse.statusCode) {
      case 200:
        return _lire(reponse.bodyBytes, rayonM);
      case 404:
        // Interrupteur éteint sur le serveur (CHOIX_CHAUFFEUR_ACTIF) : jamais
        // de nouvel essai, l'écran se ferme et la commande continue avec le
        // plus proche.
        throw const RechercheChauffeursException(
          'Le choix du chauffeur n’est pas disponible pour le moment.',
          reessayable: false,
          fonctionCoupee: true,
        );
      case 426:
        throw const RechercheChauffeursException(
          'Mets Taama à jour pour choisir ton chauffeur.',
          reessayable: false,
        );
      case 400:
        throw const RechercheChauffeursException(
          'Position introuvable.',
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
    for (final entree in liste) {
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
