import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/service_course.dart';

/// Levée par estimerCourse quand l'estimation n'est pas exploitable (réseau,
/// timeout, statut HTTP non-200, réponse racine pas une liste) — distincte
/// d'une liste vide (0 service dispo), qui n'est PAS une erreur. L'appelant
/// (résultats_recherche_screen.dart) doit basculer sur le flux statique
/// uniquement sur cette exception, jamais sur une liste vide.
class EstimationIndisponibleException implements Exception {
  final String message;
  EstimationIndisponibleException(this.message);
  @override
  String toString() => message;
}

/// Service centralisé pour tous les appels au backend Django.
/// L'URL vient de ApiConfig (voir lib/config/api_config.dart) : par défaut
/// l'IP LAN de dev, ou l'URL de prod passée via --dart-define=API_URL=...
class ApiService {
  static const String _baseUrl = ApiConfig.baseUrl;
  
  


  static const String _cleTokenPersiste = 'auth_token';

  static String? _token;


  static Future<void> definirToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token.isEmpty) {
      await prefs.remove(_cleTokenPersiste);
    } else {
      await prefs.setString(_cleTokenPersiste, token);
    }
  }

  /// À appeler une seule fois au démarrage de l'app (avant runApp), pour
  /// restaurer la session précédente si un token a été sauvegardé.
  static Future<void> chargerTokenPersiste() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_cleTokenPersiste);
  }

  static bool get estConnecte => _token != null;
  static String? get token => _token; // Exposé pour le WebSocket du chat

  static Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) headers['Authorization'] = 'Token $_token';
    return headers;
  }

  static Map<String, String> get _headersPublics => {
        'Content-Type': 'application/json',
      };

  static dynamic _traiterReponse(http.Response reponse, {int codeAttendu = 200}) {
    if (reponse.statusCode != codeAttendu) {
      String message;
      try {
        final corps = jsonDecode(reponse.body);
        message = corps['erreur'] ?? corps['detail'] ?? reponse.body;
      } catch (_) {
        message = reponse.body;
      }
      throw Exception(message);
    }
    return jsonDecode(reponse.body);
  }

  // ─── Authentification ─────────────────────────────────────────────────────

  static Future<String> demanderOtp(String telephone) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/comptes/demander-otp/'),
      headers: _headersPublics,
      body: jsonEncode({'telephone': telephone}),
    );
    final donnees = _traiterReponse(reponse);
    return donnees['code_debug']?.toString() ?? '';
  }

  static Future<void> verifierOtp(String telephone, String code) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/comptes/verifier-otp/'),
      headers: _headersPublics,
      body: jsonEncode({'telephone': telephone, 'code': code}),
    );
    final donnees = _traiterReponse(reponse);
    await definirToken(donnees['token'] as String);
  }

  static Future<Map<String, dynamic>> monProfil() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/comptes/mon-profil/'), headers: _headers);
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> modifierProfil({String? prenom, String? nom}) async {
    final corps = <String, dynamic>{};
    if (prenom != null) corps['first_name'] = prenom;
    if (nom != null) corps['last_name'] = nom;
    final reponse = await http.patch(
      Uri.parse('$_baseUrl/comptes/modifier-profil/'),
      headers: _headers,
      body: jsonEncode(corps),
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  // ─── Profil conducteur ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> monProfilChauffeur() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/chauffeur/mon-profil/'), headers: _headers);
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> creerMonProfilChauffeur({
    required String nom,
    required String typeTransport,
    required String vehicule,
    required String plaque,
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/chauffeur/creer-mon-profil/'),
      headers: _headers,
      body: jsonEncode({'nom': nom, 'type_transport': typeTransport, 'vehicule': vehicule, 'plaque': plaque}),
    );
    return _traiterReponse(reponse, codeAttendu: 201) as Map<String, dynamic>;
  }

  static Future<bool> changerDisponibilite() async {
    final reponse = await http.post(Uri.parse('$_baseUrl/trajets/chauffeur/disponibilite/'), headers: _headers);
    final donnees = _traiterReponse(reponse);
    return donnees['disponible'] as bool;
  }

  // ─── Vérification conducteur (KYC) ────────────────────────────────────────

  static Future<Map<String, dynamic>> soumettreVerification({
    required String permisPhoto,
    required String assurancePhoto,
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/chauffeur/soumettre-verification/'),
      headers: _headers,
      body: jsonEncode({
        'permis_photo': permisPhoto,
        'assurance_photo': assurancePhoto,
      }),
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> statutVerification() async {
    final reponse = await http.get(
      Uri.parse('$_baseUrl/trajets/chauffeur/statut-verification/'),
      headers: _headers,
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> calculerDistanceGPS({
    required double latDepart,
    required double lonDepart,
    required double latArrivee,
    required double lonArrivee,
    String typeTransport = 'Voiture',
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/calculer-distance/'),
      headers: _headers,
      body: jsonEncode({
        'lat_depart': latDepart,
        'lon_depart': lonDepart,
        'lat_arrivee': latArrivee,
        'lon_arrivee': lonArrivee,
        'type_transport': typeTransport,
      }),
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  /// Estimation de prix par service (POST /trajets/estimer/) — jamais de
  /// prix envoyé par le client, uniquement les 4 coordonnées. Lève
  /// [EstimationIndisponibleException] pour toute erreur réseau/HTTP/format
  /// racine (jamais de liste vide silencieuse dans ces cas-là : une liste
  /// vide signifie "0 service dispo", ce qui est un résultat valide, pas une
  /// erreur — à l'appelant de distinguer les deux).
  static Future<List<ServiceCourse>> estimerCourse({
    required double departLat,
    required double departLng,
    required double arriveeLat,
    required double arriveeLng,
  }) async {
    final http.Response reponse;
    try {
      reponse = await http.post(
        Uri.parse('$_baseUrl/trajets/estimer/'),
        headers: _headers,
        body: jsonEncode({
          'depart_lat': departLat,
          'depart_lng': departLng,
          'arrivee_lat': arriveeLat,
          'arrivee_lng': arriveeLng,
        }),
      );
    } catch (e) {
      throw EstimationIndisponibleException('Estimation indisponible (réseau) : $e');
    }

    if (reponse.statusCode != 200) {
      String message = 'Estimation indisponible (HTTP ${reponse.statusCode})';
      try {
        final corps = jsonDecode(reponse.body);
        message = corps['erreur'] ?? corps['detail'] ?? message;
      } catch (_) {
        // Corps non-JSON : on garde le message HTTP générique ci-dessus.
      }
      throw EstimationIndisponibleException(message);
    }

    final List<dynamic> brut;
    try {
      brut = jsonDecode(reponse.body) as List<dynamic>;
    } catch (e) {
      throw EstimationIndisponibleException('Réponse estimer_course invalide (pas une liste) : $e');
    }

    // Une entrée mal formée (id invalide -> FormatException de
    // ServiceCourse.fromJson) est ignorée sans faire échouer les autres —
    // un seul service en base avec un souci ne doit pas priver le client de
    // toute estimation.
    final services = <ServiceCourse>[];
    for (final entree in brut) {
      try {
        services.add(ServiceCourse.fromJson(entree as Map<String, dynamic>));
      } on FormatException catch (e) {
        debugPrint('[ApiService] Entrée estimer_course ignorée : $e');
      }
    }
    return services;
  }

  // ─── Passager : réservations existantes (règlement de l'existant) ─────────

  static Future<List<dynamic>> mesReservations() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/reservations/mes-reservations/'), headers: _headers);
    return _traiterReponse(reponse) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> annulerReservation(
    int reservationId, {
    String motif = 'autre',
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/reservations/$reservationId/annuler/'),
      headers: _headers,
      body: jsonEncode({'motif': motif}),
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  // ─── Demandes instantanées ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> creerDemandeInstantanee({
    required String destination,
    required double distanceKm,
    String? typeTransport,
    int? typeServiceId,
    DateTime? dateHeurePlanifiee,
    double? departLat,
    double? departLng,
    double? destinationLat,
    double? destinationLng,
  }) async {
    assert(
      (typeServiceId != null) != (typeTransport != null),
      'Exactement un de typeServiceId / typeTransport doit être fourni',
    );
    // L'assert ci-dessus disparaît des builds release — ce garde-fou reste
    // actif en prod, pour ne jamais poster une demande sans aucun type ni
    // avec les deux à la fois.
    if ((typeServiceId == null) == (typeTransport == null)) {
      throw ArgumentError(
          'Exactement un de typeServiceId / typeTransport doit être fourni');
    }

    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/demandes/creer/'),
      headers: _headers,
      body: jsonEncode({
        'destination': destination,
        'distance_km': double.parse(distanceKm.toStringAsFixed(1)),
        if (typeServiceId != null) 'type_service': typeServiceId,
        if (typeServiceId == null && typeTransport != null)
          'type_transport': typeTransport,
        if (dateHeurePlanifiee != null)
          'date_heure_planifiee': dateHeurePlanifiee.toIso8601String(),
        if (departLat != null) 'depart_lat': departLat,
        if (departLng != null) 'depart_lng': departLng,
        if (destinationLat != null) 'destination_lat': destinationLat,
        if (destinationLng != null) 'destination_lng': destinationLng,
      }),
    );
    return _traiterReponse(reponse, codeAttendu: 201) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> detailDemande(int demandeId) async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/demandes/$demandeId/'), headers: _headers);
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> annulerDemande(
    int demandeId, {
    String motif = 'autre',
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/demandes/$demandeId/annuler/'),
      headers: _headers,
      body: jsonEncode({'motif': motif}),
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> annulerDemandeChaufeur(
    int demandeId, {
    String motif = 'autre',
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/demandes/$demandeId/annuler-chauffeur/'),
      headers: _headers,
      body: jsonEncode({'motif': motif}),
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> mesDemandesAssignees() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/demandes/mes-demandes-assignees/'), headers: _headers);
    return _traiterReponse(reponse) as List<dynamic>;
  }

  static Future<void> accepterDemande(int demandeId) async {
    final reponse = await http.post(Uri.parse('$_baseUrl/trajets/demandes/$demandeId/accepter/'), headers: _headers);
    _traiterReponse(reponse);
  }

  static Future<void> refuserDemande(int demandeId) async {
    final reponse = await http.post(Uri.parse('$_baseUrl/trajets/demandes/$demandeId/refuser/'), headers: _headers);
    _traiterReponse(reponse);
  }

  static Future<List<dynamic>> mesDemandesClient() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/demandes/mes-demandes/'), headers: _headers);
    return _traiterReponse(reponse) as List<dynamic>;
  }

  static Future<List<dynamic>> mesDemandesPlanifiees() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/demandes/planifiees/'), headers: _headers);
    return _traiterReponse(reponse) as List<dynamic>;
  }

  // ─── Portefeuille et paiements ────────────────────────────────────────────

  static Future<int> monSolde() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/mon-solde/'), headers: _headers);
    final donnees = _traiterReponse(reponse);
    return donnees['solde'] as int;
  }

  static Future<Map<String, dynamic>> demanderRechargePaydunya({
    required String operateur,
    required int montant,
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/recharger-paydunya/'),
      headers: _headers,
      body: jsonEncode({'operateur': operateur, 'montant': montant}),
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifierRechargePaydunya({
    required int rechargeId,
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/verifier-recharge-paydunya/'),
      headers: _headers,
      body: jsonEncode({'recharge_id': rechargeId}),
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> mesRecharges() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/mes-recharges/'), headers: _headers);
    return _traiterReponse(reponse) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> payerReservation(int reservationId) async {
    final reponse = await http.post(Uri.parse('$_baseUrl/trajets/reservations/$reservationId/payer/'), headers: _headers);
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> payerDemande(int demandeId) async {
    final reponse = await http.post(Uri.parse('$_baseUrl/trajets/demandes/$demandeId/payer/'), headers: _headers);
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<List<dynamic>> mesTransactions() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/chauffeur/mes-transactions/'), headers: _headers);
    return _traiterReponse(reponse) as List<dynamic>;
  }

  static Future<List<dynamic>> mesPaiementsClient() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/mes-paiements/'), headers: _headers);
    return _traiterReponse(reponse) as List<dynamic>;
  }

  // ─── Historique conducteur ────────────────────────────────────────────────

  static Future<List<dynamic>> historiqueReservationsChauffeur() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/chauffeur/historique-reservations/'), headers: _headers);
    return _traiterReponse(reponse) as List<dynamic>;
  }

  static Future<List<dynamic>> historiqueDemandesChauffeur() async {
    final reponse = await http.get(Uri.parse('$_baseUrl/trajets/chauffeur/historique-demandes/'), headers: _headers);
    return _traiterReponse(reponse) as List<dynamic>;
  }

  // ─── Notifications push ───────────────────────────────────────────────────

  static Future<void> enregistrerTokenNotification(String token) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/trajets/notifications/enregistrer-token/'),
        headers: _headers,
        body: jsonEncode({'token': token}),
      );
    } catch (_) {}
  }

  // ─── Notation du conducteur ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> noterChauffeurReservation(
    int reservationId,
    int note,
    String commentaire,
  ) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/reservations/$reservationId/noter/'),
      headers: _headers,
      body: jsonEncode({'note': note, 'commentaire': commentaire}),
    );
    return _traiterReponse(reponse, codeAttendu: 201) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> noterChauffeurDemande(
    int demandeId,
    int note,
    String commentaire,
  ) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/demandes/$demandeId/noter/'),
      headers: _headers,
      body: jsonEncode({'note': note, 'commentaire': commentaire}),
    );
    return _traiterReponse(reponse, codeAttendu: 201) as Map<String, dynamic>;
  }

  // ─── Alertes SOS ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> declencherSOS({
    int? demandeId,
    int? reservationId,
    double? latitude,
    double? longitude,
    String message = 'Alerte SOS déclenchée',
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/sos/declencher/'),
      headers: _headers,
      body: jsonEncode({
        if (demandeId != null) 'demande_id': demandeId,
        if (reservationId != null) 'reservation_id': reservationId,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'message': message,
      }),
    );
    return _traiterReponse(reponse, codeAttendu: 201) as Map<String, dynamic>;
  }

  // ─── Avis utilisateurs ─────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> soumettreAvis({
    required int note,
    required String categorie,
    required String message,
    String versionApp = '1.0.0',
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/avis/soumettre/'),
      headers: _headers,
      body: jsonEncode({
        'note': note,
        'categorie': categorie,
        'message': message,
        'version_app': versionApp,
      }),
    );
    return _traiterReponse(reponse, codeAttendu: 201) as Map<String, dynamic>;
  }

  // ─── Service Courier ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> creerCourier({
    required String adresseCollecte,
    required String adresseLivraison,
    required String descriptionColis,
    String categorie = 'colis',
    String? telephoneDestinataire,
    double distanceKm = 5.0,
    double? latCollecte,
    double? lngCollecte,
    double? latLivraison,
    double? lngLivraison,
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/courier/creer/'),
      headers: _headers,
      body: jsonEncode({
        'adresse_collecte': adresseCollecte,
        'adresse_livraison': adresseLivraison,
        'description_colis': descriptionColis,
        'categorie': categorie,
        if (telephoneDestinataire != null && telephoneDestinataire.isNotEmpty)
          'telephone_destinataire': telephoneDestinataire,
        'distance_km': double.parse(distanceKm.toStringAsFixed(1)),
        if (latCollecte != null) 'lat_collecte': latCollecte,
        if (lngCollecte != null) 'lng_collecte': lngCollecte,
        if (latLivraison != null) 'lat_livraison': latLivraison,
        if (lngLivraison != null) 'lng_livraison': lngLivraison,
      }),
    );
    return _traiterReponse(reponse, codeAttendu: 201) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> detailCourier(int courierId) async {
    final reponse = await http.get(
      Uri.parse('$_baseUrl/trajets/courier/$courierId/'),
      headers: _headers,
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> payerCourier(int courierId) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/courier/$courierId/payer/'),
      headers: _headers,
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  // ─── Catalogue des services ─────────────────────────────────────────────────

  static Future<List<dynamic>> listeServices() async {
    final reponse = await http.get(
      Uri.parse('$_baseUrl/trajets/services/'),
      headers: {'Content-Type': 'application/json'},
    );
    return _traiterReponse(reponse) as List<dynamic>;
  }

  static Future<List<dynamic>> conducteursProches({
    required double lat,
    required double lng,
    String? typeTransport,
  }) async {
    final params = {
      'lat': lat.toString(),
      'lng': lng.toString(),
      if (typeTransport != null) 'type': typeTransport,
    };
    final uri = Uri.parse('$_baseUrl/trajets/conducteurs/proches/')
        .replace(queryParameters: params);
    final reponse = await http.get(uri, headers: _headers);
    return _traiterReponse(reponse) as List<dynamic>;
  }
}