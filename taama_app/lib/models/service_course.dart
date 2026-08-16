/// Modèle mappé sur la réponse JSON de POST /trajets/estimer/ — un service
/// (TypeService côté backend) avec sa disponibilité/prix pour un trajet
/// donné (dépendants du point de départ envoyé).
class ServiceCourse {
  final int id;
  final String nom;
  final String description;
  final String typeVehicule;
  final bool necessiteClimatisation;
  final bool disponible;
  final int? prix;
  final int? etaMinutes;
  final int placesMax;
  final int conducteursProches;

  const ServiceCourse({
    required this.id,
    required this.nom,
    required this.description,
    required this.typeVehicule,
    required this.necessiteClimatisation,
    required this.disponible,
    required this.prix,
    required this.etaMinutes,
    required this.placesMax,
    required this.conducteursProches,
  });

  /// Parse défensif : un champ manquant ou mal typé retombe sur une valeur
  /// par défaut plutôt que de faire planter le parsing — la réponse backend
  /// peut évoluer (nouveau champ, champ renommé) sans casser une app pas
  /// encore mise à jour.
  factory ServiceCourse.fromJson(Map<String, dynamic> json) {
    // id : jamais de défaut silencieux — un id invalide/manquant/<=0 serait
    // reposté tel quel comme `type_service` à la création de la demande
    // (fichier 4), donc une valeur bidon (0) créerait une demande avec un
    // mauvais service plutôt que d'échouer visiblement ici.
    final idBrut = json['id'];
    final id = idBrut is int ? idBrut : int.tryParse(idBrut?.toString() ?? '');
    if (id == null || id <= 0) {
      throw FormatException('ServiceCourse.fromJson : id invalide ou manquant ($idBrut)');
    }

    return ServiceCourse(
      id: id,
      nom: json['nom']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      typeVehicule: json['type_vehicule']?.toString() ?? '',
      necessiteClimatisation: json['necessite_climatisation'] as bool? ?? false,
      disponible: json['disponible'] as bool? ?? false,
      prix: (json['prix'] as num?)?.toInt(),
      etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
      placesMax: (json['places_max'] as num?)?.toInt() ?? 0,
      conducteursProches: (json['conducteurs_proches'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Le service DISPONIBLE, non climatisé, au prix le plus bas — utilisé pour
/// proposer un repli quand le service choisi par le client est indisponible.
/// Fonction pure, sans dépendance UI : testable isolément (voir
/// test/service_course_test.dart).
ServiceCourse? trouverStandardDeRepli(List<ServiceCourse> services) {
  final candidats = services.where(
    (s) => s.disponible && !s.necessiteClimatisation && s.prix != null,
  );
  if (candidats.isEmpty) return null;

  return candidats.reduce((a, b) => a.prix! <= b.prix! ? a : b);
}
