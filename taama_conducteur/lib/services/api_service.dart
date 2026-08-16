import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

/// Erreur renvoyée par le backend, avec son code HTTP conservé — permet aux
/// écrans de distinguer un 409 (conflit, ex. double-accept) d'un 404
/// (ressource introuvable/expirée) plutôt que de tout traiter en erreur
/// générique. `toString()` reste au format `Exception: message` pour rester
/// compatible avec le code existant qui fait `e.toString().replaceAll('Exception: ', '')`.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'Exception: $message';
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
      throw ApiException(reponse.statusCode, message);
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

  static Future<Map<String, dynamic>> uploaderPhotoProfil(File photo) async {
    final requete = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/trajets/chauffeur/photo-profil/'),
    );
    requete.headers.addAll(_headers..remove('Content-Type'));
    requete.files.add(await http.MultipartFile.fromPath('photo', photo.path));

    final reponseStream = await requete.send();
    final reponse = await http.Response.fromStream(reponseStream);
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

  /// Pousse la position GPS actuelle du conducteur — à la connexion puis en
  /// continu tant qu'il est en ligne (déclenché par LocationService).
  static Future<void> envoyerPositionChauffeur({
    required double lat,
    required double lng,
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/chauffeur/position/'),
      headers: _headers,
      body: jsonEncode({'lat': lat, 'lng': lng}),
    );
    _traiterReponse(reponse);
  }

  /// Signale au serveur que le conducteur n'est plus en ligne (logout, mise
  /// en veille) : il ne sera plus proposé dans les recherches de proximité.
  static Future<void> deconnexionChauffeur() async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/chauffeur/deconnexion/'),
      headers: _headers,
    );
    _traiterReponse(reponse);
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
    required String typeTransport,
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
    required String typeTransport,
    DateTime? dateHeurePlanifiee,
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/demandes/creer/'),
      headers: _headers,
      body: jsonEncode({
        'destination': destination,
        'distance_km': double.parse(distanceKm.toStringAsFixed(1)),
        'type_transport': typeTransport,
        if (dateHeurePlanifiee != null)
          'date_heure_planifiee': dateHeurePlanifiee.toIso8601String(),
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

  /// Retourne la demande mise à jour (statut 'en_route') — notamment
  /// client_telephone, qui n'est renvoyé par le backend qu'à partir de ce
  /// statut (jamais avant acceptation). Ne pas se fier à une copie de la
  /// demande récupérée AVANT cet appel : elle aura client_telephone = null.
  static Future<Map<String, dynamic>> accepterDemande(int demandeId) async {
    final reponse = await http.post(Uri.parse('$_baseUrl/trajets/demandes/$demandeId/accepter/'), headers: _headers);
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  static Future<void> refuserDemande(int demandeId) async {
    final reponse = await http.post(Uri.parse('$_baseUrl/trajets/demandes/$demandeId/refuser/'), headers: _headers);
    _traiterReponse(reponse);
  }

  static Future<Map<String, dynamic>> terminerCourse(int demandeId) async {
    final reponse = await http.post(Uri.parse('$_baseUrl/trajets/demandes/$demandeId/terminer/'), headers: _headers);
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }

  /// Signale que le conducteur a récupéré le client au point de départ —
  /// démarre la 2e jambe (vers la destination) côté backend.
  static Future<Map<String, dynamic>> marquerClientABord(int demandeId) async {
    final reponse = await http.post(Uri.parse('$_baseUrl/trajets/demandes/$demandeId/client-a-bord/'), headers: _headers);
    return _traiterReponse(reponse) as Map<String, dynamic>;
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

  static Future<List<dynamic>> mesLivraisonsCourier() async {
    final reponse = await http.get(
      Uri.parse('$_baseUrl/trajets/courier/mes-livraisons/'),
      headers: _headers,
    );
    return _traiterReponse(reponse) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> changerStatutCourier(
    int courierId, {
    String? photoLivraison,
  }) async {
    final reponse = await http.post(
      Uri.parse('$_baseUrl/trajets/courier/$courierId/statut/'),
      headers: _headers,
      body: jsonEncode({
        if (photoLivraison != null) 'photo_livraison': photoLivraison,
      }),
    );
    return _traiterReponse(reponse) as Map<String, dynamic>;
  }
}