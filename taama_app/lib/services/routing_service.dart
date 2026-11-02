import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';

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
          .get(url, headers: {'User-Agent': AppConfig.userAgentHttp})
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

  /// Tracé + durée + distance en UN appel OSRM (au lieu de deux). Null sur
  /// toute erreur : l'appelant n'affiche alors aucun temps, jamais un 0.
  /// Minutes arrondies au-dessus, minimum 1.
  static Future<({List<LatLng> trace, int minutes, double km})?> calculerItineraire({
    required LatLng depart,
    required LatLng arrivee,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/route/v1/driving/'
        '${depart.longitude},${depart.latitude};'
        '${arrivee.longitude},${arrivee.latitude}'
        '?overview=full&geometries=geojson',
      );
      final reponse = await http
          .get(url, headers: {'User-Agent': AppConfig.userAgentHttp})
          .timeout(const Duration(seconds: 12));
      if (reponse.statusCode != 200) return null;
      return lireItineraire(reponse.body);
    } catch (_) {
      return null;
    }
  }

  /// Lecture d'une réponse OSRM /route (séparée pour être testable sans
  /// réseau). Null si la réponse est inexploitable.
  static ({List<LatLng> trace, int minutes, double km})? lireItineraire(String corps) {
    try {
      final donnees = jsonDecode(corps) as Map<String, dynamic>;
      final routes = donnees['routes'] as List?;
      if (donnees['code'] != 'Ok' || routes == null || routes.isEmpty) return null;
      final route = routes[0] as Map<String, dynamic>;
      final coords = route['geometry']?['coordinates'] as List?;
      final secondes = route['duration'];
      final metres = route['distance'];
      if (coords == null || coords.length < 2 || secondes is! num || metres is! num) {
        return null;
      }
      return (
        trace: [
          for (final p in coords)
            LatLng(((p as List)[1] as num).toDouble(), (p[0] as num).toDouble()),
        ],
        minutes: math.max(1, (secondes / 60).ceil()),
        km: metres / 1000,
      );
    } catch (_) {
      return null;
    }
  }

  /// Durée estimée (minutes, arrondie) entre deux points via OSRM — même
  /// service que recupererItineraire, mais `overview=false` (on n'a pas
  /// besoin du tracé ici, juste routes[0]['duration'] en secondes que les
  /// autres méthodes de ce fichier récupèrent déjà mais n'exploitent pas).
  /// Ne lève jamais : `null` sur toute erreur, l'appelant doit alors ne
  /// pas afficher de durée plutôt que d'en inventer une.
  static Future<int?> dureeMinutesVers({
    required LatLng depart,
    required LatLng arrivee,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/route/v1/driving/'
        '${depart.longitude},${depart.latitude};'
        '${arrivee.longitude},${arrivee.latitude}'
        '?overview=false',
      );
      final reponse = await http
          .get(url, headers: {'User-Agent': AppConfig.userAgentHttp})
          .timeout(const Duration(seconds: 8));
      if (reponse.statusCode != 200) return null;

      final donnees = jsonDecode(reponse.body) as Map<String, dynamic>;
      if (donnees['code'] != 'Ok') return null;

      final routes = donnees['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final dureeSecondes = routes[0]['duration'];
      if (dureeSecondes is! num) return null;
      return (dureeSecondes / 60).round();
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
          .get(url, headers: {'User-Agent': AppConfig.userAgentHttp})
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
