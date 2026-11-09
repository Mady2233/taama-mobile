// lib/models/course_historique.dart
//
// Une course de « Mes courses » (GET chauffeur/mes-courses/). Champ absent ou
// illisible : null, et l'écran masque la ligne (jamais « null » affiché).

import 'dart:math' as math;

import '../donnees/carte_bamako.dart';

/// Au-delà, le point est hors des quartiers connus : aucun nom plutôt qu'un
/// nom faux.
const double _ecartMaxQuartierKm = 3;

/// Quartier le plus proche d'un point, ou null (point inconnu ou hors carte).
String? quartierLePlusProche(double? lat, double? lng) {
  if (lat == null || lng == null || quartiersBamako.isEmpty) return null;
  QuartierCarte? meilleur;
  var ecartMin = double.infinity;
  for (final q in quartiersBamako) {
    final dLat = lat - q.lat;
    final dLng = (lng - q.lng) * 0.976; // cos(12,6°) : latitude de Bamako
    final ecart = dLat * dLat + dLng * dLng;
    if (ecart < ecartMin) {
      ecartMin = ecart;
      meilleur = q;
    }
  }
  final km = math.sqrt(ecartMin) * 111.32;
  return km <= _ecartMaxQuartierKm ? meilleur?.nom : null;
}

class CourseHistorique {
  const CourseHistorique({
    required this.id,
    required this.statut,
    required this.creeLe,
    required this.destination,
    required this.prix,
    required this.modePaiement,
    this.accepteLe,
    this.distanceKm,
    this.typeTransport,
    this.categorie,
    this.quartierDepart,
    this.quartierDestination,
    this.commission,
    this.montantChauffeur,
    this.prixStandard,
    this.passager,
    this.noteRecue,
    this.annuleePar,
    this.motifAnnulation,
  });

  final int id;
  final String statut;
  final DateTime creeLe;
  final DateTime? accepteLe;
  final String destination;
  final double? distanceKm;
  final String? typeTransport;
  final String? categorie;
  final String? quartierDepart;
  final String? quartierDestination;

  /// Ce que le client a payé (ou devait payer), promo comprise.
  final int? prix;
  final String modePaiement;

  /// Seulement après un vrai paiement dans l'app : sinon null, rien d'inventé.
  final int? commission;
  final int? montantChauffeur;

  /// Prix standard quand le client a accepté un autre prix proposé.
  final int? prixStandard;
  final String? passager;
  final int? noteRecue;
  final String? annuleePar;
  final String? motifAnnulation;

  bool get terminee => statut == 'termine';
  bool get annulee => statut == 'annule';
  bool get payeeDansLApp => modePaiement == 'portefeuille';

  /// Null si l'entrée est inexploitable (id, statut ou date manquants).
  static CourseHistorique? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final id = (brut['id'] as num?)?.toInt();
    final statut = brut['statut']?.toString();
    final creeLe = DateTime.tryParse(brut['cree_le']?.toString() ?? '')?.toLocal();
    if (id == null || statut == null || creeLe == null) return null;
    int? entier(Object? v) => v is num ? v.toInt() : null;
    double? reel(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    String? texte(Object? v) {
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final ajuste = brut['prix_ajuste'];
    final annulation = brut['annulation'];
    return CourseHistorique(
      id: id,
      statut: statut,
      creeLe: creeLe,
      accepteLe: DateTime.tryParse(brut['accepte_le']?.toString() ?? '')?.toLocal(),
      destination: texte(brut['destination']) ?? 'Destination',
      distanceKm: reel(brut['distance_km']),
      typeTransport: texte(brut['type_transport']),
      categorie: texte(brut['categorie']),
      quartierDepart: quartierLePlusProche(reel(brut['depart_lat']), reel(brut['depart_lng'])),
      quartierDestination: quartierLePlusProche(reel(brut['destination_lat']), reel(brut['destination_lng'])),
      prix: entier(brut['prix']),
      modePaiement: brut['mode_paiement'] == 'portefeuille' ? 'portefeuille' : 'especes',
      commission: entier(brut['commission']),
      montantChauffeur: entier(brut['montant_chauffeur']),
      prixStandard: ajuste is Map ? entier(ajuste['standard']) : null,
      passager: texte(brut['passager']),
      noteRecue: entier(brut['note_recue']),
      annuleePar: annulation is Map ? texte(annulation['par']) : null,
      motifAnnulation: annulation is Map ? texte(annulation['motif']) : null,
    );
  }
}

/// Totaux d'un jour, calculés par le serveur sur toute la journée.
class TotalJour {
  const TotalJour(this.courses, this.total);
  final int courses;
  final int total;
}
