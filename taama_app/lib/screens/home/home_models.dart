// lib/screens/home/home_models.dart
//
// Modèles d'affichage de l'accueil. Ré-exportés par home_screen.dart, donc
// `import 'home_screen.dart';` suffit (comme avant).

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// ⚠️ À aligner sur les choices `type_transport` du backend.
/// 'Moto' est confirmé (home_page.dart le compare déjà) ; vérifier 'Voiture'.
abstract final class CodesTransport {
  static const String moto = 'Moto';
  static const String voiture = 'Voiture';
}

enum TypeAdresse { domicile, travail, autre }

@immutable
class ConducteurProche {
  const ConducteurProche({
    required this.id,
    required this.nomCourt,
    required this.position,
    this.urlPhoto,
    this.note,
    this.modeleVehicule,
    this.minutesAvant,
    this.estMoto = true,
  });

  final String id;
  final String nomCourt;
  final LatLng position;
  final String? urlPhoto;
  final double? note;
  final String? modeleVehicule;
  final int? minutesAvant;
  final bool estMoto;
}

@immutable
class SuggestionDestination {
  const SuggestionDestination({
    required this.id,
    required this.libelle,
    required this.type,
    this.dureeMinutes,
  });

  final String id;
  final String libelle;
  final TypeAdresse type;
  final int? dureeMinutes;
}

/// Service affiché sur une tuile. [prixMinFcfa] vient UNIQUEMENT du serveur
/// (endpoint tarifs-min à créer) : jamais de prix calculé côté app.
@immutable
class ServiceAccueil {
  const ServiceAccueil({
    required this.code,
    required this.libelle,
    this.prixMinFcfa,
  });

  final String code;
  final String libelle;
  final int? prixMinFcfa;
}

@immutable
class DerniereCourse {
  const DerniereCourse({required this.destination, this.prixFcfa});

  final String destination;
  final int? prixFcfa;
}
