import 'dart:math' as math;

/// Point géographique (WGS84), indépendant de `latlong2`.
class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  bool get estValide =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

enum TypeVehicule {
  moto('moto'),
  voiture('voiture');

  const TypeVehicule(this.code);

  /// Valeur échangée avec l'API.
  final String code;

  static TypeVehicule? depuisCode(Object? code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// Chauffeur disponible autour du client, tel que renvoyé par
/// `GET /api/chauffeurs/proches/` (contrat dans BRIEF_CLAUDE_CODE.md).
class ChauffeurProche {
  const ChauffeurProche({
    required this.id,
    required this.jeton,
    required this.nomAffiche,
    required this.typeVehicule,
    required this.modeleVehicule,
    required this.couleurVehicule,
    required this.note,
    required this.verifie,
    required this.tarifKm,
    required this.distanceM,
    required this.etaMin,
    required this.position,
  });

  /// Identifiant stable et pseudonyme (propre à ce client). Sert uniquement
  /// à l'affichage : sélection, animations.
  final String id;

  /// Jeton signé à durée de vie courte, renvoyé tel quel pour demander ce
  /// chauffeur. Opaque : ne jamais le décoder ni le stocker.
  final String jeton;

  /// Nom tel que le serveur choisit de l'afficher (recommandé : « Seydou K. »).
  final String nomAffiche;
  final TypeVehicule typeVehicule;
  final String modeleVehicule;
  final String couleurVehicule;

  /// null : chauffeur sans note suffisante (affiché « Nouveau »).
  final double? note;
  final bool verifie;

  /// Tarif au km en francs CFA, fixé par le serveur. Affichage seulement :
  /// le prix d'une course reste toujours calculé côté serveur.
  final int tarifKm;
  final int distanceM;
  final int etaMin;

  /// Position arrondie par le serveur (~100 m).
  final GeoPoint position;

  List<String> get _mots =>
      nomAffiche.split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();

  String get prenom {
    final mots = _mots;
    return mots.isEmpty ? nomAffiche : mots.first;
  }

  String get initiales {
    final mots = _mots;
    if (mots.isEmpty) return '?';
    String premiere(String mot) =>
        String.fromCharCode(mot.runes.first).toUpperCase();
    return mots.length == 1
        ? premiere(mots.first)
        : premiere(mots.first) + premiere(mots[1]);
  }

  /// Renvoie null si l'entrée est invalide : une entrée corrompue est
  /// ignorée au lieu de faire échouer tout l'écran.
  static ChauffeurProche? depuisJson(Object? json) {
    if (json is! Map) return null;

    final id = _texte(json['id'], max: 64);
    final jeton = _texte(json['jeton'], max: 512);
    final nom = _texte(json['nom_affiche'], max: 60);
    final type = TypeVehicule.depuisCode(json['type_vehicule']);
    final lat = _nombre(json['lat']);
    final lng = _nombre(json['lng']);
    final tarif = _nombre(json['tarif_km']);
    final distance = _nombre(json['distance_m']);
    final eta = _nombre(json['eta_min']);

    if (id == null ||
        jeton == null ||
        nom == null ||
        type == null ||
        lat == null ||
        lng == null ||
        tarif == null ||
        distance == null ||
        eta == null) {
      return null;
    }

    final position = GeoPoint(lat, lng);
    if (!position.estValide || tarif <= 0 || distance < 0 || eta < 0) {
      return null;
    }

    final note = _nombre(json['note']);
    return ChauffeurProche(
      id: id,
      jeton: jeton,
      nomAffiche: nom,
      typeVehicule: type,
      modeleVehicule: _texte(json['modele_vehicule'], max: 40) ?? '',
      couleurVehicule: _texte(json['couleur_vehicule'], max: 20) ?? '',
      note: (note != null && note >= 0 && note <= 5) ? note : null,
      verifie: json['verifie'] == true,
      tarifKm: tarif.round(),
      distanceM: distance.round(),
      // Jamais « 0 min » : un chauffeur ne se téléporte pas.
      etaMin: math.max(1, eta.round()),
      position: position,
    );
  }
}

String? _texte(Object? valeur, {required int max}) {
  if (valeur is! String) return null;
  final texte = valeur.trim();
  if (texte.isEmpty) return null;
  return texte.length > max ? texte.substring(0, max) : texte;
}

/// Accepte un nombre JSON ou une chaîne numérique (DRF sérialise les
/// `DecimalField` en chaîne, ex. « 150.00 »).
double? _nombre(Object? valeur) {
  if (valeur is num) return valeur.isFinite ? valeur.toDouble() : null;
  if (valeur is String) {
    final d = double.tryParse(valeur.trim());
    return (d != null && d.isFinite) ? d : null;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Formatage (français, sans dépendance à `intl`).
// ---------------------------------------------------------------------------

String _virgule(String texte) => texte.replaceAll('.', ',');

/// 640 → « 640 m », 1100 → « 1,1 km ».
String formaterDistance(int metres) {
  if (metres < 950) return '${math.max(10, (metres / 10).round() * 10)} m';
  return '${_virgule((metres / 1000).toStringAsFixed(1))} km';
}

/// 3000 → « 3 km » (libellés des anneaux du radar).
String formaterRayon(int metres) =>
    metres % 1000 == 0 ? '${metres ~/ 1000} km' : formaterDistance(metres);

/// 4.8 → « 4,8 ».
String formaterNote(double note) => _virgule(note.toStringAsFixed(1));

/// 150 → « 150 F/km », 1500 → « 1 500 F/km ».
String formaterTarifKm(int fcfa) => '${formaterEntier(fcfa)} F/km';

/// Séparateur de milliers : espace fine insécable.
String formaterEntier(int valeur) {
  final chiffres = valeur.abs().toString();
  final tampon = StringBuffer(valeur < 0 ? '-' : '');
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) tampon.write(' ');
    tampon.write(chiffres[i]);
  }
  return tampon.toString();
}
