// Couche « Uber-like » de la carte : noms de quartiers et repères de Bamako
// (OpenStreetMap, lib/donnees/carte_bamako.dart), et attribution toujours
// visible. Fichier identique dans taama_app et taama_conducteur.
//
// À placer dans les children d'un FlutterMap :
//   FondCarteTaama(...),             // lib/carte/fond_carte.dart
//   const CoucheCarteTaama(),        // juste après le fond
//   ... itinéraire, marqueurs ...
//   const AttributionCarteTaama(),   // en DERNIER, toujours visible
//
// Si l'attribution n'est pas à sa place par défaut (bas gauche, marge 6),
// passer la même position aux deux :
//   CoucheCarteTaama(reserves: [ZoneReservee.attribution(alignement: a, marge: m)]),
//   AttributionCarteTaama(alignement: a, marge: m),
//
// Navigation : CoucheCarteTaama(densite: DensiteEtiquettes.navigation) —
// moins d'étiquettes, plus espacées, seulement les grands repères.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/carte_config.dart';
import '../donnees/carte_bamako.dart';
import '../theme/couleurs_carte.dart';

/// Zone de la carte où aucune étiquette n'est posée (attribution, bouton
/// superposé…). Exprimée comme un widget aligné dans la carte : même
/// alignement et même marge que l'élément qu'elle protège.
class ZoneReservee {
  const ZoneReservee({
    required this.alignement,
    required Size this.taille,
    this.marge = EdgeInsets.zero,
  });

  /// Zone de l'attribution placée avec ces mêmes paramètres ; sa taille est
  /// mesurée (elle dépend de la taille de texte choisie par l'utilisateur).
  const ZoneReservee.attribution({
    this.alignement = Alignment.bottomLeft,
    this.marge = AttributionCarteTaama.margeParDefaut,
  }) : taille = null;

  final Alignment alignement;
  final Size? taille;
  final EdgeInsets marge;

  Rect dans(Size carte, TextScaler echelle, TextStyle base) => alignement.inscribe(
      taille ?? AttributionCarteTaama.mesurer(echelle, base),
      marge.deflateRect(Offset.zero & carte));
}

/// Combien d'étiquettes, et lesquelles.
enum DensiteEtiquettes {
  /// Cartes consultées à l'arrêt (accueil, suivi, commande).
  normale(plafond: 40, sousQuartiers: true, importanceMax: 3, ecartX: 6, ecartY: 3),

  /// Navigation : un coup d'œil en conduisant. Grands quartiers et grands
  /// repères seulement, peu nombreux et bien espacés.
  navigation(plafond: 12, sousQuartiers: false, importanceMax: 1, ecartX: 12, ecartY: 6);

  const DensiteEtiquettes({
    required this.plafond,
    required this.sousQuartiers,
    required this.importanceMax,
    required this.ecartX,
    required this.ecartY,
  });

  /// Étiquettes au plus par écran.
  final int plafond;
  final bool sousQuartiers;

  /// Importance maximale des repères affichés (1 = grands repères).
  final int importanceMax;

  /// Écart minimal autour du texte d'une étiquette (horizontal, vertical).
  final double ecartX;
  final double ecartY;
}

/// Catégories listées dans [texte] (« pharmacie, banque »). Une catégorie
/// inconnue est ignorée, jamais une erreur.
Set<CategorieRepere> categoriesDuFond(String texte) => {
      for (final nom in texte.split(','))
        ...CategorieRepere.values.where((c) => c.name == nom.trim()),
    };

/// Repères que le fond de carte dessine déjà (CARTE_REPERES_FOND) : la
/// couche Taama ne les répète pas.
final Set<CategorieRepere> reperesDessinesParLeFond =
    categoriesDuFond(CarteConfig.reperesDuFond);

/// Noms de quartiers que le fond dessine déjà.
enum QuartiersMasques {
  aucun,

  /// Grands quartiers seulement : les sous-quartiers restent affichés.
  principaux,
  tous,
}

/// « tous », « principaux » ; toute autre valeur (vide, inconnue) : aucun.
QuartiersMasques quartiersDuFond(String texte) => switch (texte.trim()) {
      'tous' => QuartiersMasques.tous,
      'principaux' => QuartiersMasques.principaux,
      _ => QuartiersMasques.aucun,
    };

/// Valeur fixée au build (CARTE_QUARTIERS_FOND).
final QuartiersMasques quartiersDessinesParLeFond =
    quartiersDuFond(CarteConfig.quartiersDuFond);

/// Quartiers et repères visibles au zoom courant, du plus important au
/// moins important. Une étiquette est omise si son rectangle (texte mesuré,
/// plus un petit écart) touche celui d'une étiquette déjà placée, ou une
/// [ZoneReservee]. Plafond par écran : lisible et léger sur un téléphone
/// d'entrée de gamme. Aucune requête réseau.
class CoucheCarteTaama extends StatefulWidget {
  const CoucheCarteTaama({
    super.key,
    this.nuit = false,
    this.densite = DensiteEtiquettes.normale,
    this.reserves = const [ZoneReservee.attribution()],
    this.reperesMasques,
    this.quartiersMasques,
  });

  final bool nuit;
  final DensiteEtiquettes densite;
  final List<ZoneReservee> reserves;

  /// Catégories de repères à ne jamais afficher. Null : celles que le fond
  /// dessine déjà (CARTE_REPERES_FOND).
  final Set<CategorieRepere>? reperesMasques;

  /// Noms de quartiers à ne pas afficher. Null : ceux que le fond dessine
  /// déjà (CARTE_QUARTIERS_FOND).
  final QuartiersMasques? quartiersMasques;

  // Zoom minimal d'apparition.
  static const double zoomQuartiers = 12;
  static const double zoomSousQuartiers = 14;
  static const Map<int, double> zoomRepere = {1: 13, 2: 15, 3: 16};

  /// Largeur maximale d'une étiquette (au-delà : points de suspension).
  static const double largeurMax = 170;

  @override
  State<CoucheCarteTaama> createState() => _CoucheCarteTaamaState();
}

/// Tous les candidats, triés une fois pour toutes : quartiers d'abord (on se
/// repère à Bamako par quartier), grands puis sous-quartiers ; ensuite
/// grands repères, repères courants, pharmacies.
final List<_Candidat> _candidatsTries = () {
  final liste = <_Candidat>[
    for (final q in quartiersBamako)
      _Candidat(
        LatLng(q.lat, q.lng),
        q.principal ? 0 : 1,
        zoomMin: q.principal
            ? CoucheCarteTaama.zoomQuartiers
            : CoucheCarteTaama.zoomSousQuartiers,
        importance: 0,
        quartier: q,
      ),
    for (final r in reperesBamako)
      _Candidat(
        LatLng(r.lat, r.lng),
        _prioriteRepere(importanceRepere[r.categorie] ?? 3),
        zoomMin: CoucheCarteTaama.zoomRepere[importanceRepere[r.categorie] ?? 3] ?? 16,
        importance: importanceRepere[r.categorie] ?? 3,
        repere: r,
      ),
  ];
  liste.sort((a, b) => a.priorite.compareTo(b.priorite));
  return liste;
}();

int _prioriteRepere(int importance) =>
    importance == 1 ? 2 : (importance == 2 ? 3 : 4);

// Styles servant AUSSI à la mesure : une seule définition, sinon la taille
// mesurée et la taille affichée divergent.
TextStyle _styleQuartier(bool principal) => TextStyle(
      fontSize: principal ? 12 : 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: principal ? 1.8 : 1.4,
    );
const TextStyle _styleRepere = TextStyle(fontSize: 11, fontWeight: FontWeight.w700);
const double _pastille = 20;
const double _espacePastille = 4;

/// Taille affichée d'une étiquette, mesurée une fois par nom et par taille
/// de texte de l'utilisateur.
final Map<String, Size> _tailles = {};

/// [base] : style de texte effectif de l'écran (police du thème). Sans lui,
/// la mesure se ferait dans une autre police que l'affichage.
Size _taille(_Candidat c, TextScaler echelle, TextStyle base) {
  final cle = '${base.fontFamily}|${echelle.scale(10)}|'
      '${c.quartier != null ? 'q${c.quartier!.principal}' : 'r'}|'
      '${c.quartier?.nom ?? c.repere!.nom}';
  return _tailles[cle] ??= () {
    final repere = c.repere != null;
    final reserve = repere ? _pastille + _espacePastille : 0.0;
    final tp = TextPainter(
      text: TextSpan(
        text: repere ? c.repere!.nom : c.quartier!.nom.toUpperCase(),
        style: base.merge(repere ? _styleRepere : _styleQuartier(c.quartier!.principal)),
      ),
      textDirection: TextDirection.ltr,
      textScaler: echelle,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: CoucheCarteTaama.largeurMax - reserve);
    final taille = Size(tp.width + reserve, math.max(tp.height, repere ? _pastille : 0));
    tp.dispose();
    return taille;
  }();
}

class _Place {
  const _Place(this.candidat, this.taille);
  final _Candidat candidat;
  final Size taille;
}

class _CoucheCarteTaamaState extends State<CoucheCarteTaama> {
  // Sélection valable pour une zone plus large que la vue : un glissement
  // de carte ne recalcule pas les collisions entre étiquettes. Recalcul au
  // changement de palier de zoom (0,5), de taille de texte, ou quand la vue
  // sort de la zone. Seul le test contre les zones réservées (fixes à
  // l'écran) est refait à chaque image : au plus 160 rectangles.
  double? _palier;
  double? _echelle;
  DensiteEtiquettes? _densite;
  Set<CategorieRepere>? _masques;
  QuartiersMasques? _quartiersMasques;
  LatLngBounds? _zone;
  List<_Place> _places = const [];

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    if (camera.zoom < CoucheCarteTaama.zoomQuartiers) return const SizedBox.shrink();
    final echelle = MediaQuery.textScalerOf(context);
    final palier = (camera.zoom * 2).floorToDouble() / 2;
    final vue = camera.visibleBounds;
    final zone = _zone;
    final masques = widget.reperesMasques ?? reperesDessinesParLeFond;
    final quartiersMasques = widget.quartiersMasques ?? quartiersDessinesParLeFond;
    if (palier != _palier ||
        echelle.scale(10) != _echelle ||
        widget.densite != _densite ||
        !identical(masques, _masques) ||
        quartiersMasques != _quartiersMasques ||
        zone == null ||
        !zone.containsBounds(vue)) {
      _palier = palier;
      _echelle = echelle.scale(10);
      _densite = widget.densite;
      _masques = masques;
      _quartiersMasques = quartiersMasques;
      final nouvelleZone = _elargir(vue);
      _zone = nouvelleZone;
      _places = _selectionner(camera, nouvelleZone, palier, echelle,
          DefaultTextStyle.of(context).style, widget.densite, masques, quartiersMasques);
    }

    final base = DefaultTextStyle.of(context).style;
    final reservees = [for (final z in widget.reserves) z.dans(camera.size, echelle, base)];
    // Une étiquette coupée par le bord de la carte (« …ARCHÉ DE DARSAL… »)
    // n'aide personne : elle n'apparaît qu'entière.
    final ecran = Offset.zero & camera.size;
    final marqueurs = <Marker>[];
    for (final p in _places) {
      if (marqueurs.length >= widget.densite.plafond) break;
      final rect = Rect.fromCenter(
          center: camera.latLngToScreenOffset(p.candidat.point),
          width: p.taille.width,
          height: p.taille.height);
      if (!_contient(ecran, rect) || reservees.any(rect.overlaps)) continue;
      marqueurs.add(Marker(
        point: p.candidat.point,
        width: p.taille.width + 2,
        height: math.max(p.taille.height, 26),
        child: IgnorePointer(
          child: p.candidat.quartier != null
              ? _EtiquetteQuartier(p.candidat.quartier!, nuit: widget.nuit)
              : _EtiquetteRepere(p.candidat.repere!, nuit: widget.nuit),
        ),
      ));
    }
    return MarkerLayer(markers: marqueurs);
  }

  static bool _contient(Rect exterieur, Rect r) =>
      r.left >= exterieur.left && r.top >= exterieur.top &&
      r.right <= exterieur.right && r.bottom <= exterieur.bottom;

  static LatLngBounds _elargir(LatLngBounds b) {
    final dLat = (b.north - b.south) / 2;
    final dLng = (b.east - b.west) / 2;
    return LatLngBounds(
      LatLng(math.max(-90, b.south - dLat), math.max(-180, b.west - dLng)),
      LatLng(math.min(90, b.north + dLat), math.min(180, b.east + dLng)),
    );
  }

  List<_Place> _selectionner(
      MapCamera camera, LatLngBounds zone, double palier, TextScaler echelle,
      TextStyle base, DensiteEtiquettes densite, Set<CategorieRepere> masques,
      QuartiersMasques quartiersMasques) {
    // Rectangles mesurés au palier (≤ zoom réel) : à l'écran les étiquettes
    // ne peuvent que s'écarter, jamais se rapprocher.
    final occupes = <Rect>[];
    final places = <_Place>[];
    for (final c in _candidatsTries) {
      // Zone ≈ 4 écrans : 4 fois le plafond d'un écran.
      if (places.length >= densite.plafond * 4) break;
      if (palier < c.zoomMin || !zone.contains(c.point)) continue;
      if (c.quartier != null && !c.quartier!.principal && !densite.sousQuartiers) continue;
      if (c.quartier != null &&
          (quartiersMasques == QuartiersMasques.tous ||
              (quartiersMasques == QuartiersMasques.principaux && c.quartier!.principal))) {
        continue;
      }
      if (c.repere != null &&
          (c.importance > densite.importanceMax || masques.contains(c.repere!.categorie))) {
        continue;
      }
      final taille = _taille(c, echelle, base);
      final rect = Rect.fromCenter(
        center: camera.projectAtZoom(c.point, palier),
        width: taille.width + 2 * densite.ecartX,
        height: taille.height + 2 * densite.ecartY,
      );
      if (occupes.any(rect.overlaps)) continue;
      occupes.add(rect);
      places.add(_Place(c, taille));
    }
    return places;
  }
}

class _Candidat {
  _Candidat(this.point, this.priorite,
      {required this.zoomMin, required this.importance, this.quartier, this.repere});
  final LatLng point;
  final int priorite;
  final double zoomMin;
  final int importance;
  final QuartierCarte? quartier;
  final RepereCarte? repere;
}

List<Shadow> _halo(Color couleur) => [
      for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)])
        Shadow(color: couleur, offset: d, blurRadius: 2.5),
    ];

class _EtiquetteQuartier extends StatelessWidget {
  const _EtiquetteQuartier(this.quartier, {required this.nuit});
  final QuartierCarte quartier;
  final bool nuit;

  @override
  Widget build(BuildContext context) {
    final principal = quartier.principal;
    return Center(
      child: Text(
        quartier.nom.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: _styleQuartier(principal).copyWith(
          color: nuit
              ? (principal ? CouleursCarte.quartierNuit : CouleursCarte.sousQuartierNuit)
              : (principal ? CouleursCarte.quartierJour : CouleursCarte.sousQuartierJour),
          shadows: _halo(nuit ? CouleursCarte.haloNuit : CouleursCarte.haloJour),
        ),
      ),
    );
  }
}

const Map<CategorieRepere, IconData> _icones = {
  CategorieRepere.marche: Icons.storefront_rounded,
  CategorieRepere.hopital: Icons.local_hospital_rounded,
  CategorieRepere.gare: Icons.directions_bus_rounded,
  CategorieRepere.universite: Icons.school_rounded,
  CategorieRepere.centreCommercial: Icons.shopping_bag_rounded,
  CategorieRepere.pont: Icons.alt_route_rounded,
  CategorieRepere.clinique: Icons.medical_services_rounded,
  CategorieRepere.culte: Icons.place_rounded,
  CategorieRepere.carburant: Icons.local_gas_station_rounded,
  CategorieRepere.banque: Icons.account_balance_rounded,
  CategorieRepere.police: Icons.local_police_rounded,
  CategorieRepere.pharmacie: Icons.local_pharmacy_rounded,
};

class _EtiquetteRepere extends StatelessWidget {
  const _EtiquetteRepere(this.repere, {required this.nuit});
  final RepereCarte repere;
  final bool nuit;

  @override
  Widget build(BuildContext context) {
    final halo = nuit ? CouleursCarte.haloNuit : CouleursCarte.haloJour;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _pastille,
          height: _pastille,
          decoration: BoxDecoration(
            color: CouleursCarte.pastille[repere.categorie],
            shape: BoxShape.circle,
            border: Border.all(color: halo, width: 2),
          ),
          child: Icon(_icones[repere.categorie], size: 11, color: CouleursCarte.iconeRepere),
        ),
        const SizedBox(width: _espacePastille),
        Flexible(
          child: Text(
            repere.nom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _styleRepere.copyWith(
              color: nuit ? CouleursCarte.repereNuit : CouleursCarte.repereJour,
              shadows: _halo(halo),
            ),
          ),
        ),
      ],
    );
  }
}

/// Remplace les tuiles quand le fond de carte n'est pas configuré, ou que le
/// fournisseur refuse la clé (voir FondCarteTaama) : un message clair ;
/// marqueurs, itinéraire et attribution restent dessinés au-dessus.
class FondCarteIndisponible extends StatelessWidget {
  const FondCarteIndisponible({super.key, this.nuit = false});

  final bool nuit;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: nuit ? CouleursCarte.fondIndisponibleNuit : CouleursCarte.fondIndisponibleJour,
      child: Center(
        child: Text(
          'Carte indisponible pour le moment',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: nuit ? CouleursCarte.attributionTexteNuit : CouleursCarte.attributionTexteJour,
          ),
        ),
      ),
    );
  }
}

/// Attribution exigée par OpenStreetMap (ODbL) et par le fournisseur du fond
/// (texte fixé au build : CARTE_ATTRIBUTION, voir CarteConfig), TOUJOURS visible
/// (pas un bouton replié). À placer en dernier dans les children du
/// FlutterMap ; `marge` la garde hors des barres et panneaux superposés.
class AttributionCarteTaama extends StatelessWidget {
  const AttributionCarteTaama({
    super.key,
    this.nuit = false,
    this.alignement = Alignment.bottomLeft,
    this.marge = margeParDefaut,
  });

  final bool nuit;
  final Alignment alignement;
  final EdgeInsets marge;

  static const String texte = CarteConfig.attribution;
  static const EdgeInsets margeParDefaut = EdgeInsets.all(6);
  static const TextStyle _style = TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600);
  static const EdgeInsets _interieur = EdgeInsets.symmetric(horizontal: 5, vertical: 2);

  /// Taille à l'écran (texte + fond), pour ZoneReservee.attribution.
  static Size mesurer(TextScaler echelle, TextStyle base) {
    final tp = TextPainter(
      text: TextSpan(text: texte, style: base.merge(_style)),
      textDirection: TextDirection.ltr,
      textScaler: echelle,
      maxLines: 1,
    )..layout();
    final taille = _interieur.inflateSize(tp.size);
    tp.dispose();
    return taille;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignement,
      child: Padding(
        padding: marge,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: nuit ? CouleursCarte.attributionFondNuit : CouleursCarte.attributionFondJour,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: _interieur,
              child: Text(
                texte,
                maxLines: 1,
                style: _style.copyWith(
                  color: nuit ? CouleursCarte.attributionTexteNuit : CouleursCarte.attributionTexteJour,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
