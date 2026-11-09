// lib/screens/preciser_point_rue.dart
//
// Rue trop longue pour un seul point (LieuTrouve.aPreciser) : le client place le
// point exact sur la carte, centrée sur la rue, avant toute estimation. Jamais un
// prix calculé sur un point choisi à sa place.

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/recherche_lieux.dart';
import 'courier_selection_point.dart';

/// Le lieu tel quel s'il n'y a rien à préciser ; sinon le point confirmé sur la
/// carte (null si le client revient sans confirmer).
Future<LieuTrouve?> preciserSiNecessaire(BuildContext context, LieuTrouve lieu) async {
  if (!lieu.aPreciser) return lieu;
  final point = await Navigator.push<PointCourier>(
    context,
    MaterialPageRoute(
      builder: (_) => EcranSelectionPointCourier(
        estCollecte: false,
        pointInitial: PointCourier(LatLng(lieu.lat, lieu.lng), lieu.adresse),
        titre: 'Où exactement, ${lieu.nom} ?',
        libelleConfirmation: 'Confirmer la destination',
      ),
    ),
  );
  if (point == null) return null;
  return LieuTrouve(
    nom: lieu.nom,
    detail: lieu.detail,
    adresse: point.adresse,
    lat: point.position.latitude,
    lng: point.position.longitude,
  );
}
