// lib/widgets/taama/couche_conducteurs_animes.dart
//
// Couche flutter_map : les chauffeurs proches GLISSENT de leur ancienne
// position à la nouvelle (1,2 s) au lieu de sauter, avec une petite flèche
// qui indique leur direction. À placer dans `FlutterMap.children`.
//
// - Saut > 2 km (GPS aberrant, chauffeur réapparu) : pas d'animation.
// - Au plus [maxMarqueurs] marqueurs dessinés (batterie, lisibilité).
// - « Réduire les animations » activé : positions appliquées directement.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../screens/home/home_models.dart';
import '../../theme/taama_theme.dart';

class CoucheConducteursAnimes extends StatefulWidget {
  const CoucheConducteursAnimes({
    super.key,
    required this.conducteurs,
    this.maxMarqueurs = 30,
  });

  final List<ConducteurProche> conducteurs;
  final int maxMarqueurs;

  @override
  State<CoucheConducteursAnimes> createState() => _CoucheConducteursAnimesState();
}

class _CoucheConducteursAnimesState extends State<CoucheConducteursAnimes>
    with SingleTickerProviderStateMixin {
  static const Duration _duree = Duration(milliseconds: 1200);
  static const double _sautMaxMetres = 2000;
  static const double _mouvementMinMetres = 5;
  static const Distance _distance = Distance();

  late final AnimationController _controleur =
      AnimationController(vsync: this, duration: _duree, value: 1);

  Map<String, LatLng> _depart = {};
  Map<String, LatLng> _arrivee = {};
  final Map<String, double> _caps = {};

  @override
  void initState() {
    super.initState();
    _arrivee = {for (final c in _visibles) c.id: c.position};
    _depart = Map.of(_arrivee);
  }

  List<ConducteurProche> get _visibles =>
      widget.conducteurs.take(widget.maxMarqueurs).toList(growable: false);

  @override
  void didUpdateWidget(covariant CoucheConducteursAnimes ancien) {
    super.didUpdateWidget(ancien);
    if (identical(ancien.conducteurs, widget.conducteurs)) return;

    final actuelles = _positionsCourantes();
    final depart = <String, LatLng>{};
    final arrivee = <String, LatLng>{};

    for (final c in _visibles) {
      final avant = actuelles[c.id];
      arrivee[c.id] = c.position;
      if (avant == null) {
        depart[c.id] = c.position; // nouveau chauffeur : apparaît sur place
        continue;
      }
      final metres = _distance.as(LengthUnit.Meter, avant, c.position);
      if (metres > _sautMaxMetres) {
        depart[c.id] = c.position; // saut aberrant : pas de glissade
        _caps.remove(c.id);
      } else {
        depart[c.id] = avant;
        if (metres > _mouvementMinMetres) _caps[c.id] = _cap(avant, c.position);
      }
    }
    _caps.removeWhere((id, _) => !arrivee.containsKey(id));
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

  /// Cap en radians (0 = nord, sens horaire).
  static double _cap(LatLng a, LatLng b) {
    final lat1 = a.latitudeInRad;
    final lat2 = b.latitudeInRad;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controleur,
      builder: (context, _) {
        final positions = _positionsCourantes();
        return MarkerLayer(
          markers: [
            for (final c in _visibles)
              if (positions[c.id] != null)
                Marker(
                  key: ValueKey('conducteur-${c.id}'),
                  point: positions[c.id]!,
                  width: 48,
                  height: 48,
                  child: _MarqueurConducteur(estMoto: c.estMoto, cap: _caps[c.id]),
                ),
          ],
        );
      },
    );
  }
}

class _MarqueurConducteur extends StatelessWidget {
  const _MarqueurConducteur({required this.estMoto, required this.cap});

  final bool estMoto;
  final double? cap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: estMoto ? 'Moto à proximité' : 'Voiture à proximité',
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (cap != null)
            Transform.rotate(
              angle: cap!,
              child: const SizedBox.expand(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Icon(Icons.arrow_drop_up, size: 22, color: TaamaColors.navy),
                ),
              ),
            ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: TaamaColors.navy,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: TaamaShadows.floating,
            ),
            child: Icon(
              estMoto ? Icons.two_wheeler : Icons.directions_car_filled,
              size: 16,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
