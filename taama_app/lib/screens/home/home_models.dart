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

  /// Une entrée de conducteurs/proches/ ; null si elle est inexploitable (pas
  /// de coordonnées valides). Identifiant lu comme un texte (pseudonyme du
  /// serveur), photo facultative (le serveur ne l'envoie plus). Même lecture
  /// que les builds installés depuis le 31/10 : test/conducteur_proche_test.dart.
  static ConducteurProche? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final id = brut['id']?.toString();
    final lat = (brut['lat'] as num?)?.toDouble();
    final lng = (brut['lng'] as num?)?.toDouble();
    if (id == null || lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;

    final noteBrute = brut['note'];
    return ConducteurProche(
      id: id,
      nomCourt: (brut['nom_court'] ?? '').toString(),
      position: LatLng(lat, lng),
      urlPhoto: _urlHttpsOuNull(brut['photo_profil']),
      note: noteBrute == null ? null : double.tryParse(noteBrute.toString()),
      modeleVehicule: brut['vehicule'] as String?,
      minutesAvant: (brut['temps_minutes'] as num?)?.toInt(),
      estMoto: brut['type_transport'] == CodesTransport.moto,
    );
  }

  static String? _urlHttpsOuNull(Object? valeur) {
    if (valeur is! String) return null;
    final uri = Uri.tryParse(valeur);
    return (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) ? valeur : null;
  }
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

/// Course en cours du client (non terminée), pour proposer de reprendre le
/// suivi depuis l'accueil après un retour d'arrière-plan ou une sortie de
/// l'écran de suivi.
@immutable
class CourseActive {
  const CourseActive({
    required this.id,
    required this.destination,
    required this.typeTransport,
    required this.statut,
  });

  final int id;
  final String destination;
  final String typeTransport;
  final String statut;

  /// Libellé court de l'état, pour le bandeau de reprise. Statuts de
  /// DemandeInstantanee.STATUT_CHOICES (backend).
  String get libelleEtat => switch (statut) {
        'en_recherche' => 'Recherche d’un chauffeur…',
        'chauffeur_trouve' => 'Chauffeur en route',
        'en_route' => 'Votre chauffeur arrive',
        'client_a_bord' => 'Course en cours',
        _ => 'Course en cours',
      };
}
