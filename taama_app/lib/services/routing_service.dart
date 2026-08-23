import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Récupère le tracé réel d'un itinéraire routier via OSRM (même service
/// public que le backend utilise pour le calcul de distance, voir
/// `taama_backend/trajets/routing.py`) — utilisé ici uniquement pour
/// l'affichage (le prix reste calculé côté serveur).
///
/// Ne lève JAMAIS : sur toute erreur (timeout, réponse non-200, code OSRM
/// différent de 'Ok'), renvoie `null` — l'appelant doit prévoir un repli
/// (ex. ligne droite entre les deux points).
class RoutingService {
  static const String _baseUrl = 'https://router.project-osrm.org';

  static Future<List<LatLng>?> recupererItineraire({
    required LatLng depart,
    required LatLng arrivee,
  }) async {
    try {
      // ⚠️ OSRM attend lng,lat (pas lat,lng) — même ordre que côté backend.
      final url = Uri.parse(
        '$_baseUrl/route/v1/driving/'
        '${depart.longitude},${depart.latitude};'
        '${arrivee.longitude},${arrivee.latitude}'
        '?overview=full&geometries=geojson',
      );
      final reponse = await http
          .get(url, headers: {'User-Agent': 'TaamaApp/1.0'})
          .timeout(const Duration(seconds: 8));
      if (reponse.statusCode != 200) return null;

      final donnees = jsonDecode(reponse.body) as Map<String, dynamic>;
      if (donnees['code'] != 'Ok') return null;

      final routes = donnees['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final coords = routes[0]['geometry']?['coordinates'] as List?;
      if (coords == null || coords.isEmpty) return null;

      // GeoJSON renvoie [lng, lat] par point.
      return coords
          .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Variante multi-points (arrêts intermédiaires) : UN SEUL appel OSRM
  /// couvrant tout le trajet, dans l'ordre exact de `points` (au moins 2).
  /// Même contrat que recupererItineraire : ne lève jamais, `null` en cas
  /// d'échec — l'appelant doit prévoir un repli (ligne droite).
  static Future<List<LatLng>?> recupererItineraireMulti(
      List<LatLng> points) async {
    if (points.length < 2) return null;
    try {
      final coordsUrl =
          points.map((p) => '${p.longitude},${p.latitude}').join(';');
      final url = Uri.parse(
        '$_baseUrl/route/v1/driving/$coordsUrl?overview=full&geometries=geojson',
      );
      final reponse = await http
          .get(url, headers: {'User-Agent': 'TaamaApp/1.0'})
          .timeout(const Duration(seconds: 8));
      if (reponse.statusCode != 200) return null;

      final donnees = jsonDecode(reponse.body) as Map<String, dynamic>;
      if (donnees['code'] != 'Ok') return null;

      final routes = donnees['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final coords = routes[0]['geometry']?['coordinates'] as List?;
      if (coords == null || coords.isEmpty) return null;

      return coords
          .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
          .toList();
    } catch (_) {
      return null;
    }
  }
}
