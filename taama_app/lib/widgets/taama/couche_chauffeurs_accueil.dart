// lib/widgets/taama/couche_chauffeurs_accueil.dart
//
// Couche flutter_map de l'accueil : les chauffeurs proches en pastilles à
// initiales, avec leur temps d'approche, regroupées quand elles se
// toucheraient à l'écran (les positions sont arrondies à ~110 m : deux
// voisins tombent souvent sur le même point). Les plus proches portent une
// étiquette « Prénom ★ 4,8 · 2 min » (jamais tous : la carte resterait
// illisible). Toucher une pastille ouvre la fiche du ou des chauffeurs, sans
// rien commander.
//
// Reprend le glissement de CoucheConducteursAnimes, qu'elle remplace :
// - les positions GLISSENT de l'ancienne à la nouvelle (1,2 s) ;
// - saut > 2 km (GPS aberrant, chauffeur réapparu) : pas d'animation ;
// - « réduire les animations » activé : positions appliquées directement.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../features/recherche_chauffeur/chauffeur_proche.dart' show formaterNote;
import '../../screens/home/home_models.dart';
import '../../theme/taama_theme.dart';
import 'vehicule_vu_dessus.dart';

/// Chauffeurs dont les pastilles se toucheraient : montrés d'une seule.
class GroupeChauffeurs {
  const GroupeChauffeurs(this.chauffeurs, this.position);

  /// Dans l'ordre reçu du serveur : le plus proche d'abord.
  final List<ConducteurProche> chauffeurs;

  /// Centre des membres (à moins d'une pastille les uns des autres).
  final LatLng position;

  ConducteurProche get premier => chauffeurs.first;

  /// Temps d'approche le plus court du groupe, null si aucun n'est connu.
  int? get minutes {
    int? plusCourt;
    for (final c in chauffeurs) {
      final m = c.minutesAvant;
      if (m != null && (plusCourt == null || m < plusCourt)) plusCourt = m;
    }
    return plusCourt;
  }
}

/// Regroupe les chauffeurs dont les centres sont à moins de [seuilPixels] à
/// l'écran ([versEcran] : la projection de la carte, recalculée à chaque
/// zoom). Parcours dans l'ordre d'entrée (le serveur envoie le plus proche
/// d'abord) : chaque chauffeur rejoint le premier groupe assez proche.
List<GroupeChauffeurs> grouperParEcran(
  List<(ConducteurProche, LatLng)> entrees,
  Offset Function(LatLng) versEcran, {
  double seuilPixels = 44,
}) {
  final membres = <List<(ConducteurProche, LatLng)>>[];
  final ancres = <Offset>[];
  for (final entree in entrees) {
    final ecran = versEcran(entree.$2);
    var place = false;
    for (var i = 0; i < ancres.length; i++) {
      if ((ancres[i] - ecran).distance < seuilPixels) {
        membres[i].add(entree);
        place = true;
        break;
      }
    }
    if (!place) {
      membres.add([entree]);
      ancres.add(ecran);
    }
  }
  return [
    for (final groupe in membres)
      GroupeChauffeurs(
        [for (final (c, _) in groupe) c],
        LatLng(
          groupe.map((e) => e.$2.latitude).reduce((a, b) => a + b) / groupe.length,
          groupe.map((e) => e.$2.longitude).reduce((a, b) => a + b) / groupe.length,
        ),
      ),
  ];
}

/// Côté de l'étiquette de chaque pastille qui en demande une (true : à
/// gauche), par index dans [centres] ; absent : pas d'étiquette. [largeurs] :
/// largeur de l'étiquette demandée (depuis le centre de la pastille), null
/// pour une pastille sans étiquette. Dans l'ordre (le plus proche d'abord),
/// chaque étiquette essaie le côté tourné vers le milieu de l'écran, puis
/// l'autre ; elle ne doit ni sortir de l'écran, ni toucher une étiquette déjà
/// posée, ni une autre pastille (avec son « N min » dessous). Aucun côté
/// libre : pas d'étiquette, la pastille garde ses minutes.
Map<int, bool> placerEtiquettes({
  required List<Offset> centres,
  required List<double?> largeurs,
  required Size ecran,
  double rayon = 20,
  double hauteur = 28,
}) {
  // Chaque pastille avec ses minutes dessous (jusqu'à +44) : une étiquette
  // refusée laisse réapparaître ses minutes, jamais sous une autre.
  final pastilles = [
    for (final c in centres) Rect.fromLTRB(c.dx - rayon, c.dy - rayon, c.dx + rayon, c.dy + 44),
  ];
  final posees = <Rect>[];
  final cotes = <int, bool>{};
  for (var i = 0; i < centres.length; i++) {
    final largeur = largeurs[i];
    if (largeur == null) continue;
    final c = centres[i];
    for (final aGauche in c.dx > ecran.width / 2 ? const [true, false] : const [false, true]) {
      final etiquette = aGauche
          ? Rect.fromLTRB(c.dx - largeur, c.dy - hauteur / 2, c.dx - rayon, c.dy + hauteur / 2)
          : Rect.fromLTRB(c.dx + rayon, c.dy - hauteur / 2, c.dx + largeur, c.dy + hauteur / 2);
      final libre = etiquette.left >= 0 &&
          etiquette.right <= ecran.width &&
          !posees.any(etiquette.overlaps) &&
          ![for (var j = 0; j < pastilles.length; j++) if (j != i) pastilles[j]].any(etiquette.overlaps);
      if (libre) {
        cotes[i] = aGauche;
        posees.add(etiquette);
        break;
      }
    }
  }
  return cotes;
}

class CoucheChauffeursAccueil extends StatefulWidget {
  const CoucheChauffeursAccueil({
    super.key,
    required this.conducteurs,
    required this.onGroupe,
    this.nuit = false,
    this.maxMarqueurs = 30,
    this.etiquetes = 3,
  });

  final List<ConducteurProche> conducteurs;

  /// Pastille touchée : la fiche du ou des chauffeurs (aucune commande ici).
  final ValueChanged<List<ConducteurProche>> onGroupe;

  final bool nuit;
  final int maxMarqueurs;

  /// Les [etiquetes] premiers chauffeurs reçus (les plus proches) portent
  /// leur prénom et leur note, s'ils ne sont pas dans un groupe.
  final int etiquetes;

  @override
  State<CoucheChauffeursAccueil> createState() => _CoucheChauffeursAccueilState();
}

class _CoucheChauffeursAccueilState extends State<CoucheChauffeursAccueil>
    with SingleTickerProviderStateMixin {
  static const Duration _duree = Duration(milliseconds: 1200);
  static const double _sautMaxMetres = 2000;
  static const Distance _distance = Distance();

  late final AnimationController _controleur =
      AnimationController(vsync: this, duration: _duree, value: 1);

  Map<String, LatLng> _depart = {};
  Map<String, LatLng> _arrivee = {};

  /// Direction de chaque véhicule (radians depuis le nord), déduite de ses
  /// deux dernières positions : le serveur n'en envoie pas, et les positions
  /// arrondies à ~110 m n'en donnent qu'une approximative. Tant qu'un
  /// chauffeur n'a pas bougé : une orientation fixe tirée de son pseudonyme
  /// (sinon toutes les voitures regarderaient le nord).
  final Map<String, double> _caps = {};

  double _cap(String id) => _caps[id] ?? capInitial(id);

  @override
  void initState() {
    super.initState();
    _arrivee = {for (final c in _visibles) c.id: c.position};
    _depart = Map.of(_arrivee);
  }

  List<ConducteurProche> get _visibles =>
      widget.conducteurs.take(widget.maxMarqueurs).toList(growable: false);

  @override
  void didUpdateWidget(covariant CoucheChauffeursAccueil ancien) {
    super.didUpdateWidget(ancien);
    if (identical(ancien.conducteurs, widget.conducteurs)) return;

    final actuelles = _positionsCourantes();
    final depart = <String, LatLng>{};
    final arrivee = <String, LatLng>{};
    for (final c in _visibles) {
      final avant = actuelles[c.id];
      arrivee[c.id] = c.position;
      final metres = avant == null ? null : _distance.as(LengthUnit.Meter, avant, c.position);
      if (metres == null || metres > _sautMaxMetres) {
        depart[c.id] = c.position; // nouveau, ou saut aberrant : sur place
      } else {
        depart[c.id] = avant!;
        // Au moins une case de la grille : sinon, l'arrondi seul fait pivoter.
        if (metres >= 50) _caps[c.id] = capEntre(avant, c.position);
      }
    }
    _depart = depart;
    _arrivee = arrivee;

    if (MediaQuery.disableAnimationsOf(context)) {
      _controleur.value = 1;
    } else {
      _controleur.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  Map<String, LatLng> _positionsCourantes() {
    final t = Curves.easeInOut.transform(_controleur.value);
    return {
      for (final e in _arrivee.entries)
        e.key: _interpoler(_depart[e.key] ?? e.value, e.value, t),
    };
  }

  static LatLng _interpoler(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  @override
  Widget build(BuildContext context) {
    // Reconstruite à chaque déplacement ou zoom : les groupes suivent l'écran.
    final camera = MapCamera.of(context);
    return AnimatedBuilder(
      animation: _controleur,
      builder: (context, _) {
        final positions = _positionsCourantes();
        final groupes = grouperParEcran(
          [
            for (final c in _visibles)
              if (positions[c.id] != null) (c, positions[c.id]!),
          ],
          camera.latLngToScreenOffset,
        );
        final plusProches = {
          for (final c in _visibles.take(widget.etiquetes)) c.id,
        };
        final cotes = placerEtiquettes(
          centres: [for (final g in groupes) camera.latLngToScreenOffset(g.position)],
          largeurs: [
            for (final g in groupes)
              g.chauffeurs.length == 1 && plusProches.contains(g.premier.id)
                  ? _PastilleNommee.largeur(g.premier)
                  : null,
          ],
          ecran: camera.size,
        );
        return MarkerLayer(
          markers: [
            for (final (i, groupe) in groupes.indexed)
              if (cotes[i] != null)
                Marker(
                  key: ValueKey('chauffeurs-${groupe.premier.id}'),
                  point: groupe.position,
                  // Pastille au centre du marqueur, étiquette du côté libre.
                  width: 2 * _PastilleNommee.largeurEtiquetteMax + 40,
                  height: 44,
                  child: _PastilleNommee(
                    chauffeur: groupe.premier,
                    cap: _cap(groupe.premier.id),
                    aGauche: cotes[i]!,
                    onTap: () => widget.onGroupe(groupe.chauffeurs),
                  ),
                )
              else
                Marker(
                  key: ValueKey(
                      'chauffeurs-${groupe.chauffeurs.map((c) => c.id).join('-')}'),
                  point: groupe.position,
                  width: 92,
                  height: 72,
                  child: _Pastille(
                    groupe: groupe,
                    cap: _cap(groupe.premier.id),
                    nuit: widget.nuit,
                    onTap: () => widget.onGroupe(groupe.chauffeurs),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.groupe, required this.cap, required this.nuit, required this.onTap});

  final GroupeChauffeurs groupe;
  final double cap;
  final bool nuit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final seul = groupe.chauffeurs.length == 1;
    final premier = groupe.premier;
    final minutes = groupe.minutes;
    final libelle = seul
        ? '${premier.prenom}, ${premier.estMoto ? 'moto' : 'voiture'}'
            '${minutes != null ? ', environ $minutes\u00a0min' : ''}'
        : '${groupe.chauffeurs.length} chauffeurs'
            '${minutes != null ? ', le plus proche à environ $minutes\u00a0min' : ''}';
    return Semantics(
      button: true,
      label: libelle,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            seul
                ? _Vehicule(chauffeur: premier, cap: cap)
                : _RondNombre(nombre: groupe.chauffeurs.length),
            if (minutes != null) ...[
              const SizedBox(height: 3),
              _EtiquetteMinutes(minutes: minutes, nuit: nuit),
            ],
          ],
        ),
      ),
    );
  }
}

/// Le véhicule du chauffeur vu de dessus (voiture ou moto), dans le sens
/// de la marche ; les initiales restent dans la fiche.
class _Vehicule extends StatelessWidget {
  const _Vehicule({required this.chauffeur, required this.cap});

  final ConducteurProche chauffeur;
  final double cap;

  static const double taille = 40;

  /// Sur un disque blanc ombré : lisible sur toutes les rues, de jour comme
  /// de nuit, et sur le bout de son étiquette.
  @override
  Widget build(BuildContext context) => Container(
        width: taille,
        height: taille,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [BoxShadow(color: TaamaColors.ombreMarqueur, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: VehiculeVuDessus(estMoto: chauffeur.estMoto, cap: cap, taille: taille - 6),
      );
}

/// Un des chauffeurs les plus proches : sa pastille et, à côté, une
/// étiquette « Seydou ★ 4,8 · 2 min » (« Nouveau » sous 5 notes, la règle du
/// radar). Seules la pastille et l'étiquette réagissent au toucher : le reste
/// du marqueur, large pour laisser la place à l'étiquette, laisse passer les
/// gestes vers la carte.
class _PastilleNommee extends StatelessWidget {
  const _PastilleNommee({
    required this.chauffeur,
    required this.cap,
    required this.aGauche,
    required this.onTap,
  });

  final ConducteurProche chauffeur;
  final double cap;

  /// Étiquette à gauche de la pastille (chauffeur dans la moitié droite).
  final bool aGauche;
  final VoidCallback onTap;

  static const double largeurEtiquetteMax = 200;
  static const double _tailleEtoile = 13;

  // Police explicite : le texte dessiné dans la carte n'hérite pas de celle
  // de l'app. Taille fixe (textScaler à 1) : l'étiquette doit tenir sur la
  // carte ; le prénom et la note restent lisibles en grand dans la fiche.
  static const TextStyle _base = TextStyle(
    fontFamily: TaamaFonts.body,
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  /// Largeurs déjà mesurées : le placement est refait à chaque image du
  /// glissement et à chaque mouvement de la carte.
  static final Map<String, double> _largeurs = {};

  /// Largeur de l'étiquette depuis le centre de la pastille : texte mesuré,
  /// étoile, marges. Sert à placer les étiquettes sans chevauchement.
  static double largeur(ConducteurProche chauffeur) {
    final note = chauffeur.notePublique;
    final minutes = chauffeur.minutesAvant;
    final cle = '${chauffeur.prenom}|$note|$minutes';
    final connue = _largeurs[cle];
    if (connue != null) return connue;
    if (_largeurs.length > 200) _largeurs.clear();
    final mesure = TextPainter(
      text: TextSpan(style: _base, children: [
        TextSpan(text: chauffeur.prenom, style: const TextStyle(fontWeight: FontWeight.w800)),
        TextSpan(text: note != null ? '  \u00a0${formaterNote(note)}' : '  Nouveau'),
        if (minutes != null) TextSpan(text: '  ·  $minutes\u00a0min'),
      ]),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final largeur = mesure.width + (note != null ? _tailleEtoile : 0) + _Vehicule.taille / 2 + 8 + 11;
    mesure.dispose();
    return _largeurs[cle] = math.min(largeur, largeurEtiquetteMax);
  }

  @override
  Widget build(BuildContext context) {
    final note = chauffeur.notePublique;
    final minutes = chauffeur.minutesAvant;
    const base = _base;
    const r = _Vehicule.taille / 2;
    final etiquette = Container(
      constraints: const BoxConstraints(maxWidth: largeurEtiquetteMax),
      height: 28,
      // L'étiquette part du centre de la pastille, qui en cache le bout :
      // r + 8 de marge côté pastille.
      padding: EdgeInsets.only(left: aGauche ? 11 : r + 8, right: aGauche ? r + 8 : 11),
      decoration: const BoxDecoration(
        color: TaamaColors.navy,
        borderRadius: BorderRadius.all(Radius.circular(999)),
        boxShadow: [BoxShadow(color: TaamaColors.ombreMarqueur, blurRadius: 8, offset: Offset(0, 2))],
      ),
      // Ajustée au texte : sans alignment (le Container prendrait toute la
      // largeur permise), la mesure de [largeur] dit vrai.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: chauffeur.prenom, style: const TextStyle(fontWeight: FontWeight.w800)),
                const TextSpan(text: '  '),
                if (note != null) ...[
                  // Icône, pas « ★ » : le caractère n'est pas dans la police
                  // embarquée.
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.star_rounded, size: _tailleEtoile, color: TaamaColors.starOnDark),
                  ),
                  TextSpan(text: '\u00a0${formaterNote(note)}'),
                ] else
                  const TextSpan(text: 'Nouveau', style: TextStyle(color: TaamaColors.onNavyMuted)),
                if (minutes != null)
                  TextSpan(
                    text: '  ·  $minutes\u00a0min',
                    style: const TextStyle(color: TaamaColors.accentMint),
                  ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: base,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: '${chauffeur.prenom}, '
          '${note != null ? 'noté ${formaterNote(note)}' : 'nouveau chauffeur'}'
          '${minutes != null ? ', environ $minutes\u00a0min' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Étiquette : du centre de la pastille vers le côté choisi.
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: aGauche
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: etiquette,
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: aGauche
                        ? const SizedBox.shrink()
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: etiquette,
                          ),
                  ),
                ],
              ),
            ),
            _Vehicule(chauffeur: chauffeur, cap: cap),
          ],
        ),
      ),
    );
  }
}

/// Pastille d'un groupe : le nombre de chauffeurs.
class _RondNombre extends StatelessWidget {
  const _RondNombre({required this.nombre});

  final int nombre;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: TaamaColors.navy,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: TaamaShadows.floating,
      ),
      child: Text(
        '$nombre',
        textScaler: TextScaler.noScaling,
        // Police explicite : le texte dessiné dans la carte n'hérite pas de
        // celle de l'app.
        style: const TextStyle(
          fontFamily: TaamaFonts.body,
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }
}

/// « 4 min » sous la pastille : lisible en plein soleil (fond opaque, halo).
class _EtiquetteMinutes extends StatelessWidget {
  const _EtiquetteMinutes({required this.minutes, required this.nuit});

  final int minutes;
  final bool nuit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: nuit ? TaamaColors.nightRaised : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: nuit ? TaamaColors.nightBorder : Colors.white),
        boxShadow: const [BoxShadow(color: TaamaColors.ombreMarqueur, blurRadius: 6, offset: Offset(0, 1))],
      ),
      child: Text(
        '$minutes\u00a0min',
        maxLines: 1,
        style: TextStyle(
          fontFamily: TaamaFonts.body,
          color: nuit ? TaamaColors.textOnDark : TaamaColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}
