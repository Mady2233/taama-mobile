import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'chauffeur_proche.dart';

class ResultatRecherche {
  const ResultatRecherche({required this.chauffeurs, required this.rayonM});

  final List<ChauffeurProche> chauffeurs;

  /// Rayon réellement appliqué par le serveur (il peut le borner).
  final int rayonM;
}

class RechercheChauffeursException implements Exception {
  const RechercheChauffeursException(
    this.message, {
    this.reessayable = true,
    this.fonctionCoupee = false,
  });

  /// Message destiné à l'utilisateur, sans détail technique.
  final String message;

  /// false : inutile de réessayer automatiquement (session expirée,
  /// position invalide). Le rafraîchissement s'arrête.
  final bool reessayable;

  /// Vrai si le serveur a coupé le choix du chauffeur (404) : l'écran se
  /// ferme, la commande continue avec le plus proche.
  final bool fonctionCoupee;

  @override
  String toString() => 'RechercheChauffeursException($message)';
}

abstract class ChauffeursProchesRepository {
  /// [type] : celui du service choisi (le serveur ne retrouve un chauffeur
  /// choisi que parmi ceux du type du devis) ; null : tous.
  Future<ResultatRecherche> rechercher({
    required GeoPoint position,
    required int rayonM,
    TypeVehicule? type,
  });
}

/// Données factices reproduisant la maquette (4 motos, 4 voitures), avec une
/// légère dérive à chaque appel pour simuler le mouvement.
///
/// Lève une erreur en release : de faux chauffeurs ne doivent jamais
/// atteindre un vrai client.
class FauxChauffeursProchesRepository implements ChauffeursProchesRepository {
  FauxChauffeursProchesRepository({
    this.latence = const Duration(milliseconds: 600),
  }) {
    if (kReleaseMode) {
      throw StateError(
        'FauxChauffeursProchesRepository ne doit jamais être utilisé en release.',
      );
    }
  }

  final Duration latence;
  int _appels = 0;

  static const _gabarits = <_Gabarit>[
    _Gabarit('f1', 'Seydou Keïta', TypeVehicule.moto, 'Yamaha YBR', 'Noire',
        4.8, true, 1100, 50, 2),
    _Gabarit('f2', 'Ibrahim Diarra', TypeVehicule.voiture, 'Toyota Corolla',
        'Grise', 4.7, true, 1500, 313, 3),
    _Gabarit('f3', 'Moussa Traoré', TypeVehicule.moto, 'Haojue DK', 'Rouge',
        4.6, true, 1900, 246, 4),
    _Gabarit('f4', 'Fatoumata Dembélé', TypeVehicule.voiture, 'Hyundai Accent',
        'Blanche', 4.9, true, 2000, 14, 4),
    _Gabarit('f5', 'Amadou Coulibaly', TypeVehicule.voiture, 'Toyota Yaris',
        'Bleue', 4.5, true, 2300, 120, 5),
    _Gabarit('f6', 'Cheick Bah', TypeVehicule.voiture, 'Kia Picanto',
        'Blanche', 4.7, true, 2450, 204, 6),
    _Gabarit('f7', 'Lassana Touré', TypeVehicule.moto, 'Honda CG 125',
        'Noire', 4.4, false, 2600, 288, 6),
    _Gabarit('f8', 'Oumar Sangaré', TypeVehicule.moto, 'Yamaha Crux', 'Bleue',
        4.8, true, 2700, 52, 7),
  ];

  @override
  Future<ResultatRecherche> rechercher({
    required GeoPoint position,
    required int rayonM,
    TypeVehicule? type,
  }) async {
    await Future<void>.delayed(latence);
    _appels++;
    final cosLat = math.cos(position.lat * math.pi / 180);
    final chauffeurs = <ChauffeurProche>[];
    for (final g in _gabarits) {
      // Comme le serveur : seulement le type demandé.
      if (type != null && g.type != type) continue;
      final derive = math.sin(_appels * 0.8 + g.capDegres) * 45;
      final distance = math.min(g.distanceM + derive, rayonM * 0.95);
      final cap = g.capDegres * math.pi / 180;
      chauffeurs.add(ChauffeurProche(
        id: g.id,
        jeton: 'faux-${g.id}-$_appels',
        nomAffiche: g.nom,
        typeVehicule: g.type,
        modeleVehicule: g.modele,
        couleurVehicule: g.couleur,
        note: g.note,
        verifie: g.verifie,
        tarifKm: g.type == TypeVehicule.moto ? 150 : 450,
        distanceM: distance.round(),
        etaMin: g.etaMin,
        position: GeoPoint(
          position.lat + distance * math.cos(cap) / 110540,
          position.lng + distance * math.sin(cap) / (111320 * cosLat),
        ),
      ));
    }
    return ResultatRecherche(chauffeurs: chauffeurs, rayonM: rayonM);
  }
}

class _Gabarit {
  const _Gabarit(
    this.id,
    this.nom,
    this.type,
    this.modele,
    this.couleur,
    this.note,
    this.verifie,
    this.distanceM,
    this.capDegres,
    this.etaMin,
  );

  final String id;
  final String nom;
  final TypeVehicule type;
  final String modele;
  final String couleur;
  final double note;
  final bool verifie;
  final double distanceM;
  final double capDegres;
  final int etaMin;
}
