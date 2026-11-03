// Suggestions de destinations, sans réseau : quartiers et repères de Bamako déjà
// embarqués dans l'app (lib/donnees/carte_bamako.dart). Aucune data consommée, et
// la politique d'usage de Nominatim interdit de l'appeler à chaque lettre.
//
// Un lieu choisi part avec ses coordonnées : plus de géocodage à deviner sur un
// nom, donc pas de prix calculé sur un mauvais point.

import '../donnees/carte_bamako.dart';

const int _longueurMinSaisie = 2;

/// À moins de ~300 m (en degrés à la latitude de Bamako), deux lieux de même nom
/// sont le même endroit.
const double _ecartMemeLieu = 0.0027;

/// Destination renvoyée par l'écran de recherche. Sans coordonnées : saisie libre
/// ou adresse enregistrée, à géocoder.
class DestinationChoisie {
  const DestinationChoisie(this.nom, {this.lat, this.lng});

  final String nom;
  final double? lat;
  final double? lng;
}

class LieuTrouve {
  const LieuTrouve({
    required this.nom,
    required this.detail,
    required this.adresse,
    required this.lat,
    required this.lng,
  });

  final String nom;

  /// « Quartier », « Banque · Badalabougou »…
  final String detail;

  /// Texte envoyé au serveur et lu par le chauffeur : « Ecobank, Badalabougou »
  /// (74 noms de repères reviennent plusieurs fois dans Bamako).
  final String adresse;
  final double lat;
  final double lng;
}

class _Entree {
  const _Entree(this.nom, this.normalise, this.mots, this.rang, this.lat, this.lng, this.categorie);

  final String nom;
  final String normalise;
  final List<String> mots;

  /// 0 grand quartier, 1 quartier, puis repères du plus au moins important.
  final int rang;
  final double lat;
  final double lng;

  /// Null pour un quartier.
  final CategorieRepere? categorie;
}

const Map<CategorieRepere, String> _libellesCategorie = {
  CategorieRepere.marche: 'Marché',
  CategorieRepere.hopital: 'Hôpital',
  CategorieRepere.gare: 'Gare routière',
  CategorieRepere.universite: 'Université',
  CategorieRepere.centreCommercial: 'Centre commercial',
  CategorieRepere.pont: 'Pont',
  CategorieRepere.clinique: 'Clinique',
  CategorieRepere.culte: 'Lieu de culte',
  CategorieRepere.carburant: 'Station-service',
  CategorieRepere.banque: 'Banque',
  CategorieRepere.police: 'Police',
  CategorieRepere.pharmacie: 'Pharmacie',
};

const Map<String, String> _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ñ': 'n', 'œ': 'oe',
};

/// Sans accents ni majuscules, ponctuation remplacée par des espaces.
String normaliserLieu(String texte) {
  final tampon = StringBuffer();
  for (final caractere in texte.toLowerCase().split('')) {
    tampon.write(_accents[caractere] ?? caractere);
  }
  return tampon
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

// Construit une seule fois, à la première recherche.
final List<_Entree> _index = () {
  _Entree entree(String nom, int rang, double lat, double lng, CategorieRepere? categorie) {
    final normalise = normaliserLieu(nom);
    return _Entree(nom, normalise, normalise.split(' '), rang, lat, lng, categorie);
  }

  return [
    for (final q in quartiersBamako) entree(q.nom, q.principal ? 0 : 1, q.lat, q.lng, null),
    for (final r in reperesBamako)
      entree(r.nom, 1 + (importanceRepere[r.categorie] ?? 3), r.lat, r.lng, r.categorie),
  ].where((e) => e.normalise.isNotEmpty).toList();
}();

double _ecartCarre(double lat1, double lng1, double lat2, double lng2) {
  final dLat = lat1 - lat2;
  final dLng = (lng1 - lng2) * 0.976; // cos(12,6°) : latitude de Bamako
  return dLat * dLat + dLng * dLng;
}

String _quartierLePlusProche(double lat, double lng) {
  var meilleur = quartiersBamako.first;
  var ecartMin = double.infinity;
  for (final q in quartiersBamako) {
    final ecart = _ecartCarre(lat, lng, q.lat, q.lng);
    if (ecart < ecartMin) {
      ecartMin = ecart;
      meilleur = q;
    }
  }
  return meilleur.nom;
}

/// 0 : le nom commence par la saisie ; 1 : chaque mot saisi commence un mot du
/// nom ; 2 : la saisie est ailleurs dans le nom ; null : aucun rapport.
int? _score(_Entree e, String saisie, List<String> mots) {
  if (e.normalise.startsWith(saisie)) return 0;
  if (mots.every((m) => e.mots.any((mot) => mot.startsWith(m)))) return 1;
  if (e.normalise.contains(saisie)) return 2;
  return null;
}

LieuTrouve _versLieu(_Entree e) {
  final categorie = e.categorie;
  if (categorie == null) {
    return LieuTrouve(nom: e.nom, detail: 'Quartier', adresse: e.nom, lat: e.lat, lng: e.lng);
  }
  final quartier = _quartierLePlusProche(e.lat, e.lng);
  return LieuTrouve(
    nom: e.nom,
    detail: '${_libellesCategorie[categorie]} · $quartier',
    adresse: '${e.nom}, $quartier',
    lat: e.lat,
    lng: e.lng,
  );
}

/// Suggestions pour [saisie], les plus pertinentes d'abord. Vide en dessous de
/// 2 caractères.
List<LieuTrouve> rechercherLieux(String saisie, {int max = 8}) {
  final normalise = normaliserLieu(saisie);
  if (normalise.length < _longueurMinSaisie) return const [];
  final mots = normalise.split(' ');

  final trouves = <(int, _Entree)>[];
  for (final e in _index) {
    final score = _score(e, normalise, mots);
    if (score != null) trouves.add((score, e));
  }
  trouves.sort((a, b) {
    if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
    if (a.$2.rang != b.$2.rang) return a.$2.rang.compareTo(b.$2.rang);
    if (a.$2.nom.length != b.$2.nom.length) return a.$2.nom.length.compareTo(b.$2.nom.length);
    return a.$2.nom.compareTo(b.$2.nom);
  });

  // « Hopital du Mali » et « Hôpital du Mali » au même endroit : une seule ligne.
  final vus = <String>{};
  final resultats = <LieuTrouve>[];
  for (final (_, e) in trouves) {
    final lieu = _versLieu(e);
    if (!vus.add('${e.normalise}|${lieu.detail}')) continue;
    resultats.add(lieu);
    if (resultats.length >= max) break;
  }
  return resultats;
}

/// Le lieu qui porte exactement ce nom, s'il est sans ambiguïté. Null si plusieurs
/// endroits portent ce nom (21 Ecobank) : mieux vaut géocoder que deviner.
LieuTrouve? lieuExact(String nom) {
  final normalise = normaliserLieu(nom);
  if (normalise.isEmpty) return null;
  final memes = _index.where((e) => e.normalise == normalise).toList();
  if (memes.isEmpty) return null;
  final premier = memes.first;
  final limite = _ecartMemeLieu * _ecartMemeLieu;
  final unique = memes.every((e) => _ecartCarre(e.lat, e.lng, premier.lat, premier.lng) <= limite);
  return unique ? _versLieu(premier) : null;
}

/// Géocodage d'une saisie libre, limité au Grand Bamako (Kati et Sénou compris) :
/// hors de cette zone, « introuvable » plutôt qu'un prix sur un mauvais point.
Uri uriGeocodage(String texte) => Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': '$texte, Bamako, Mali',
      'format': 'json',
      'limit': '1',
      'viewbox': '-8.25,12.85,-7.70,12.30',
      'bounded': '1',
    });
