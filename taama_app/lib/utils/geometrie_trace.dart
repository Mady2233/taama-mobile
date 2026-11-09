// lib/utils/geometrie_trace.dart
//
// Accroche du véhicule suivi à l'itinéraire tracé. Une position reçue toutes
// les ~5 s, glissée en ligne droite vers la suivante, coupe les virages et
// traverse les bâtiments : projetée sur le tracé, elle suit la route.

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Au-delà, le chauffeur n'est pas sur le tracé (détour, nouvel itinéraire en
/// calcul) : sa position réelle est affichée telle quelle.
const double ecartMaxAccrocheMetres = 30;

/// Point du tracé le plus proche de [p], mesuré aux segments ; null si le
/// tracé est vide ou plus loin que [maxMetres].
LatLng? projeterSurTrace(
  LatLng p,
  List<LatLng> trace, {
  double maxMetres = ecartMaxAccrocheMetres,
}) {
  if (trace.length < 2) return null;
  // Plan local centré sur p (équirectangulaire) : suffisant sur quelques km.
  const rayonTerre = 6371000.0;
  final cosLat = math.cos(p.latitude * math.pi / 180);
  double x(LatLng q) => (q.longitude - p.longitude) * math.pi / 180 * rayonTerre * cosLat;
  double y(LatLng q) => (q.latitude - p.latitude) * math.pi / 180 * rayonTerre;

  double? meilleureDistance;
  LatLng? meilleurPoint;
  for (var i = 0; i < trace.length - 1; i++) {
    final a = trace[i];
    final b = trace[i + 1];
    final ax = x(a), ay = y(a), bx = x(b), by = y(b);
    final dx = bx - ax, dy = by - ay;
    final longueur2 = dx * dx + dy * dy;
    final t = longueur2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / longueur2).clamp(0.0, 1.0);
    final px = ax + t * dx, py = ay + t * dy;
    final distance = math.sqrt(px * px + py * py);
    if (meilleureDistance == null || distance < meilleureDistance) {
      meilleureDistance = distance;
      meilleurPoint = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
    }
  }
  return meilleureDistance != null && meilleureDistance <= maxMetres ? meilleurPoint : null;
}
