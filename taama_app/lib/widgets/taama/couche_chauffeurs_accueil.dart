// lib/widgets/taama/couche_chauffeurs_accueil.dart
//
// Couche flutter_map de l'accueil : les chauffeurs proches en pastilles à
// initiales, avec leur temps d'approche, regroupées quand elles se
// toucheraient à l'écran (les positions sont arrondies à ~110 m : deux
// voisins tombent souvent sur le même point). Toucher une pastille ouvre la
// fiche du ou des chauffeurs, sans rien commander.
//
// Reprend le glissement de CoucheConducteursAnimes, qu'elle remplace :
// - les positions GLISSENT de l'ancienne à la nouvelle (1,2 s) ;
// - saut > 2 km (GPS aberrant, chauffeur réapparu) : pas d'animation ;
// - « réduire les animations » activé : positions appliquées directement.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../features/recherche_chauffeur/widgets/avatar_chauffeur.dart';
import '../../screens/home/home_models.dart';
import '../../theme/taama_theme.dart';

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

class CoucheChauffeursAccueil extends StatefulWidget {
  const CoucheChauffeursAccueil({
    super.key,
    required this.conducteurs,
    required this.onGroupe,
    this.nuit = false,
    this.maxMarqueurs = 30,
  });

  final List<ConducteurProche> conducteurs;

  /// Pastille touchée : la fiche du ou des chauffeurs (aucune commande ici).
  final ValueChanged<List<ConducteurProche>> onGroupe;

  final bool nuit;
  final int maxMarqueurs;

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
      if (avant == null || _distance.as(LengthUnit.Meter, avant, c.position) > _sautMaxMetres) {
        depart[c.id] = c.position; // nouveau, ou saut aberrant : sur place
      } else {
        depart[c.id] = avant;
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
        return MarkerLayer(
          markers: [
            for (final groupe in groupes)
              Marker(
                key: ValueKey(
                    'chauffeurs-${groupe.chauffeurs.map((c) => c.id).join('-')}'),
                point: groupe.position,
                width: 92,
                height: 72,
                child: _Pastille(
                  groupe: groupe,
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
  const _Pastille({required this.groupe, required this.nuit, required this.onTap});

  final GroupeChauffeurs groupe;
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
                ? AvatarChauffeur(
                    graine: premier.id,
                    initiales: premier.initiales,
                    estMoto: premier.estMoto,
                    taille: 38,
                  )
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
