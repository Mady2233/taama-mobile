// lib/services/geometrie_itineraire.dart
//
// Écart du chauffeur à l'itinéraire tracé, pour décider d'un recalcul.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Au-delà, le chauffeur a quitté l'itinéraire.
const double ecartMaxItineraireMetres = 50;

/// Une mesure moins précise ne décide jamais d'un recalcul : son erreur
/// suffirait à « sortir » de la route.
const double precisionMaxEcartMetres = 30;

/// Mesures consécutives hors du tracé avant un recalcul : une seule peut
/// être un écart du GPS.
const int mesuresHorsTraceAvantRecalcul = 2;

/// Jamais deux calculs d'itinéraire plus rapprochés (serveur OSRM limité).
const Duration intervalleMinRecalcul = Duration(seconds: 15);

/// Distance (m) de [p] au tracé, mesurée aux SEGMENTS. Mesurée aux seuls
/// points du tracé, elle croyait le chauffeur sorti de la route au milieu
/// d'une longue ligne droite, où ces points sont espacés.
double distanceAuTrace(LatLng p, List<LatLng> trace) {
  if (trace.isEmpty) return double.infinity;
  if (trace.length == 1) return const Distance()(p, trace.first);
  // Plan local centré sur p (équirectangulaire) : suffisant sur quelques km.
  const rayonTerre = 6371000.0;
  final cosLat = math.cos(p.latitude * math.pi / 180);
  double x(LatLng q) => (q.longitude - p.longitude) * math.pi / 180 * rayonTerre * cosLat;
  double y(LatLng q) => (q.latitude - p.latitude) * math.pi / 180 * rayonTerre;

  var minimum = double.infinity;
  for (var i = 0; i < trace.length - 1; i++) {
    final ax = x(trace[i]), ay = y(trace[i]);
    final dx = x(trace[i + 1]) - ax, dy = y(trace[i + 1]) - ay;
    final longueur2 = dx * dx + dy * dy;
    final t = longueur2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / longueur2).clamp(0.0, 1.0);
    final px = ax + t * dx, py = ay + t * dy;
    minimum = math.min(minimum, math.sqrt(px * px + py * py));
  }
  return minimum;
}

/// La mesure ([p], précision [precisionMetres]) compte-t-elle comme hors du
/// tracé ? Jamais si elle est trop imprécise, ou sans tracé.
bool mesureHorsTrace(LatLng p, double precisionMetres, List<LatLng> trace) =>
    trace.isNotEmpty &&
    precisionMetres <= precisionMaxEcartMetres &&
    distanceAuTrace(p, trace) > ecartMaxItineraireMetres;
