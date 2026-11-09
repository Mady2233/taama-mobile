// Suggestions de destinations, sans réseau : quartiers, localités, repères et rues
// de Bamako déjà embarqués dans l'app (lib/donnees/). Aucune data consommée, et la
// politique d'usage de Nominatim interdit de l'appeler à chaque lettre.
//
// Tolère les orthographes courantes (Kalabancoura, Magnanbougou, Kinzambougou) et
// les fautes de frappe. Toujours une suggestion que le client choisit : un lieu
// choisi part avec ses coordonnées, donc pas de prix calculé sur un mauvais point.

import 'dart:math' as math;

import '../donnees/carte_bamako.dart';
import '../donnees/localites_bamako.dart';
import '../donnees/rues_bamako.dart';

const int _longueurMinSaisie = 1;

/// Au-delà, un seul point de la voie ne dit pas où aller (une avenue traverse le
/// quartier) : le client précise le point sur la carte avant toute estimation.
const int longueurAPreciserMetres = 400;

/// Rang des rues : après les quartiers, localités et repères.
const int _rangRue = 6;

/// Une saisie avec un numéro (« rue 312 ») : jamais de faute de frappe tolérée
/// sur une rue, sinon « Rue 313 » proposerait la Rue 312.
final RegExp _chiffre = RegExp(r'\d');

// Abréviations courantes, développées avant la recherche.
final RegExp _rueCollee = RegExp(r'^(?:r|rue)(?=\d)');
const Map<String, String> _abreviations = {'av': 'avenue', 'bd': 'boulevard', 'boul': 'boulevard', 'rte': 'route'};

/// « r312 », « rue312 » → « rue 312 » ; « av kasse » → « avenue kasse ». Prend
/// un texte déjà passé par [normaliserLieu].
String _developperAbreviations(String normalise) {
  final mots = normalise.replaceFirst(_rueCollee, 'rue ').split(' ');
  return mots.map((m) => _abreviations[m] ?? m).join(' ');
}

/// En dessous, chercher une orthographe à l'intérieur d'un nom ne donne que du bruit.
const int _longueurMinOrthographeDansLeNom = 4;

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
    this.aPreciser = false,
  });

  final String nom;

  /// « Quartier », « Banque · Badalabougou », « Voie · Hamdallaye »…
  final String detail;

  /// Texte envoyé au serveur et lu par le chauffeur : « Ecobank, Badalabougou »
  /// (74 noms de repères reviennent plusieurs fois dans Bamako).
  final String adresse;
  final double lat;
  final double lng;

  /// Voie trop longue pour un seul point (voir [longueurAPreciserMetres]) : le
  /// point exact se confirme sur la carte avant toute estimation.
  final bool aPreciser;
}

class _Entree {
  const _Entree(
    this.nom,
    this.normalise,
    this.mots,
    this.cle,
    this.clesMots,
    this.rang,
    this.lat,
    this.lng,
    this.categorie, {
    this.localite = false,
    this.quartierRue,
    this.longueurRue = 0,
  });

  final String nom;
  final String normalise;
  final List<String> mots;

  /// Forme phonétique du nom entier, sans espaces, et de chacun de ses mots.
  final String cle;
  final List<String> clesMots;

  /// 0 grand quartier, 1 quartier, 2 localité, puis repères du plus au moins important.
  final int rang;
  final double lat;
  final double lng;

  /// Null pour un quartier ou une localité.
  final CategorieRepere? categorie;

  /// Ville, village ou hameau du Grand Bamako, absent de la carte.
  final bool localite;

  /// Quartier de rattachement d'une rue ; null pour tout le reste.
  final String? quartierRue;

  /// Longueur de la rue dans ce quartier, en mètres.
  final int longueurRue;

  bool get rue => quartierRue != null;

  /// Quartier ou localité : ce qu'on cherche quand on tape un nom de zone.
  bool get zone => categorie == null && !rue;
}

/// Rapport entre un lieu et la saisie, du plus fort au plus faible.
enum _Rapport {
  memeNom,
  debutDuNom,
  zoneAutreOrthographe,
  zoneUneFaute,
  motsDuNom,
  dansLeNom,
  autreOrthographe,
  orthographeDansLeNom,
  uneFaute,
  deuxFautes,
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

final RegExp _diVoyelle = RegExp(r'di(?=[aeou])');
final RegExp _sonGn = RegExp(r'gn|ny|ni(?=[aeou])');
final RegExp _lettreDoublee = RegExp(r'([a-zA-Z])\1+');

/// Forme commune aux orthographes courantes à Bamako : Kalabancoura et Kalaban
/// Coura, Magnanbougou et Maniambougou, Djikoroni et Jikoroni, Faladie et Faladje.
/// Prend un texte déjà passé par [normaliserLieu].
String clePhonetique(String normalise) {
  var t = normalise.replaceAll(' ', '');
  t = t.replaceAll('qu', 'k').replaceAll('q', 'k').replaceAll('c', 'k');
  t = t.replaceAll('h', '').replaceAll('w', '');
  t = t.replaceAll('dj', 'j').replaceAll(_diVoyelle, 'j');
  t = t.replaceAll(_sonGn, 'N');
  t = t.replaceAll('nb', 'mb').replaceAll('ou', 'u').replaceAll('y', 'i');
  return t.replaceAllMapped(_lettreDoublee, (m) => m[1]!);
}

/// Distance d'édition entre [a] et le début de [b]. Renvoie [limite] + 1 dès qu'elle
/// la dépasse : inutile de finir le calcul.
int _ecartDebut(String a, String b, int limite) {
  if (b.length < a.length - limite) return limite + 1;
  final fin = math.min(b.length, a.length + limite);
  var precedente = List<int>.generate(fin + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final courante = List<int>.filled(fin + 1, 0);
    courante[0] = i;
    var minimum = i;
    for (var j = 1; j <= fin; j++) {
      final cout = a[i - 1] == b[j - 1] ? 0 : 1;
      final valeur = math.min(
        math.min(precedente[j] + 1, courante[j - 1] + 1),
        precedente[j - 1] + cout,
      );
      courante[j] = valeur;
      minimum = math.min(minimum, valeur);
    }
    if (minimum > limite) return limite + 1;
    precedente = courante;
  }
  var meilleur = limite + 1;
  for (var j = math.max(0, a.length - limite); j <= fin; j++) {
    meilleur = math.min(meilleur, precedente[j]);
  }
  return meilleur;
}

int _fautesTolerees(int longueur) => longueur >= 9 ? 2 : (longueur >= 5 ? 1 : 0);

/// Nombre de fautes entre la saisie et le début du nom ou d'un de ses mots. Null
/// au-delà de ce qui est toléré pour cette longueur.
int? _fautes(_Entree e, String cle) {
  final tolere = _fautesTolerees(cle.length);
  if (tolere == 0) return null;
  var meilleur = _ecartDebut(cle, e.cle, tolere);
  for (final mot in e.clesMots) {
    meilleur = math.min(meilleur, _ecartDebut(cle, mot, tolere));
  }
  return meilleur <= tolere ? meilleur : null;
}

// Construit une seule fois, à la première recherche.
final List<_Entree> _index = () {
  _Entree entree(
    String nom,
    int rang,
    double lat,
    double lng,
    CategorieRepere? categorie, {
    bool localite = false,
    String? quartierRue,
    int longueurRue = 0,
  }) {
    final normalise = normaliserLieu(nom);
    final mots = normalise.split(' ');
    return _Entree(
      nom,
      normalise,
      mots,
      clePhonetique(normalise),
      mots.map(clePhonetique).toList(),
      rang,
      lat,
      lng,
      categorie,
      localite: localite,
      quartierRue: quartierRue,
      longueurRue: longueurRue,
    );
  }

  return [
    for (final q in quartiersBamako) entree(q.nom, q.principal ? 0 : 1, q.lat, q.lng, null),
    for (final l in localitesBamako) entree(l.nom, 2, l.lat, l.lng, null, localite: true),
    for (final r in reperesBamako)
      entree(r.nom, 2 + (importanceRepere[r.categorie] ?? 3), r.lat, r.lng, r.categorie),
    for (final r in ruesBamako)
      entree(r.nom, _rangRue, r.lat, r.lng, null, quartierRue: r.quartier, longueurRue: r.longueur),
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

/// Rapport sans faute de frappe. Un quartier écrit autrement passe devant un repère
/// écrit pareil : quand on tape un quartier, on cherche le quartier.
_Rapport? _rapport(_Entree e, String saisie, List<String> mots, String cle) {
  if (e.normalise == saisie || e.cle == cle) return _Rapport.memeNom;
  if (e.normalise.startsWith(saisie)) return _Rapport.debutDuNom;
  final debutPhonetique = cle.length >= 2 &&
      (e.cle.startsWith(cle) || e.clesMots.any((mot) => mot.startsWith(cle)));
  if (debutPhonetique && e.zone) return _Rapport.zoneAutreOrthographe;
  if (mots.every((m) => e.mots.any((mot) => mot.startsWith(m)))) return _Rapport.motsDuNom;
  if (e.normalise.contains(saisie)) return _Rapport.dansLeNom;
  if (debutPhonetique) return _Rapport.autreOrthographe;
  if (cle.length >= _longueurMinOrthographeDansLeNom && e.cle.contains(cle)) {
    return _Rapport.orthographeDansLeNom;
  }
  return null;
}

LieuTrouve _versLieu(_Entree e) {
  final quartierRue = e.quartierRue;
  if (quartierRue != null) {
    final aPreciser = e.longueurRue > longueurAPreciserMetres;
    return LieuTrouve(
      nom: e.nom,
      detail: aPreciser ? 'Voie · $quartierRue · point à préciser sur la carte' : 'Voie · $quartierRue',
      adresse: '${e.nom}, $quartierRue',
      lat: e.lat,
      lng: e.lng,
      aPreciser: aPreciser,
    );
  }
  final categorie = e.categorie;
  if (categorie == null) {
    return LieuTrouve(
      nom: e.nom,
      detail: e.localite ? 'Localité' : 'Quartier',
      adresse: e.nom,
      lat: e.lat,
      lng: e.lng,
    );
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

/// Suggestions pour [saisie], les plus pertinentes d'abord. Une seule lettre : les
/// quartiers et localités qui commencent par elle, sans les repères.
List<LieuTrouve> rechercherLieux(String saisie, {int max = 8}) {
  final brut = normaliserLieu(saisie);
  if (brut.length < _longueurMinSaisie) return const [];
  final normalise = _developperAbreviations(brut);
  final mots = normalise.split(' ');
  final cle = clePhonetique(normalise);
  final avecNumero = _chiffre.hasMatch(normalise);

  final trouves = <(_Rapport, _Entree)>[];
  final restants = <_Entree>[];
  if (brut.length == 1) {
    for (final e in _index) {
      if (e.zone && e.normalise.startsWith(normalise)) {
        trouves.add((_Rapport.debutDuNom, e));
      }
    }
  } else {
    for (final e in _index) {
      final rapport = _rapport(e, normalise, mots, cle);
      if (rapport != null) {
        trouves.add((rapport, e));
      } else {
        restants.add(e);
      }
    }
  }

  // Fautes de frappe : un quartier bien écrit n'en attire pas un autre à sa place, et
  // les repères et les rues ne sont cherchés ainsi que si rien d'autre n'a été
  // trouvé ; jamais une rue quand la saisie porte un numéro.
  if (!trouves.any((t) => t.$2.zone)) {
    final rienTrouve = trouves.isEmpty;
    for (final e in restants) {
      if (!e.zone && !rienTrouve) continue;
      if (e.rue && avecNumero) continue;
      final fautes = _fautes(e, cle);
      if (fautes == null) continue;
      final lien = e.zone && fautes == 1
          ? _Rapport.zoneUneFaute
          : (fautes == 1 ? _Rapport.uneFaute : _Rapport.deuxFautes);
      trouves.add((lien, e));
    }
  }

  trouves.sort((a, b) {
    if (a.$1 != b.$1) return a.$1.index.compareTo(b.$1.index);
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
/// endroits portent ce nom (21 Ecobank) : mieux vaut géocoder que deviner. Jamais
/// une rue : un nom de voie tapé sans la choisir ne dit pas où sur la voie.
LieuTrouve? lieuExact(String nom) {
  final normalise = normaliserLieu(nom);
  if (normalise.isEmpty) return null;
  final memes = _index.where((e) => !e.rue && e.normalise == normalise).toList();
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
