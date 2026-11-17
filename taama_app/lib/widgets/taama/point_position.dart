// lib/widgets/taama/point_position.dart
//
// « Ma position », comme sur les cartes du téléphone : point bleu cerclé de
// blanc dans un halo, cône vers la direction suivie quand elle est connue,
// gris tant que la position n'est que la dernière connue du téléphone (pas
// encore confirmée par le GPS). Le cercle de précision, en mètres, est
// dessiné à part par la carte (CircleLayer) : il suit le zoom.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/taama_theme.dart';

class PointPosition extends StatelessWidget {
  const PointPosition({
    super.key,
    this.cap,
    this.approximatif = false,
    this.taille = 96,
  });

  /// Direction suivie, en degrés depuis le nord (sens horaire) ; null :
  /// pas de cône (à l'arrêt, ou direction inconnue).
  final double? cap;

  /// Dernière position connue du téléphone, pas encore confirmée : gris.
  final bool approximatif;

  final double taille;

  static const double diametrePoint = 18;
  static const double diametreHalo = 40;

  @override
  Widget build(BuildContext context) {
    final couleur = approximatif ? TaamaColors.positionAncienne : TaamaColors.position;
    final cap = approximatif ? null : this.cap;
    return Semantics(
      label: approximatif ? 'Ma position, approximative' : 'Ma position',
      child: SizedBox.square(
        dimension: taille,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (cap != null)
              CustomPaint(
                key: const ValueKey('cone-direction'),
                size: Size.square(taille),
                painter: _Cone(cap: cap, couleur: couleur),
              ),
            Container(
              width: diametreHalo,
              height: diametreHalo,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: couleur.withValues(alpha: 0.16),
              ),
            ),
            Container(
              key: const ValueKey('point-position'),
              width: diametrePoint,
              height: diametrePoint,
              decoration: BoxDecoration(
                color: couleur,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(color: TaamaColors.ombreMarqueur, blurRadius: 6, offset: Offset(0, 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faisceau de 70° vers [cap], qui s'estompe en s'éloignant du point.
class _Cone extends CustomPainter {
  _Cone({required this.cap, required this.couleur});

  final double cap;
  final Color couleur;

  static const double _ouverture = 70 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final rayon = size.shortestSide / 2;
    // 0° du canvas : vers l'est ; le cap part du nord.
    final milieu = (cap - 90) * math.pi / 180;
    final peinture = Paint()
      ..shader = RadialGradient(
        colors: [
          couleur.withValues(alpha: 0.7),
          couleur.withValues(alpha: 0.45),
          couleur.withValues(alpha: 0),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: centre, radius: rayon));
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: rayon),
      milieu - _ouverture / 2,
      _ouverture,
      true,
      peinture,
    );
  }

  @override
  bool shouldRepaint(_Cone ancien) => ancien.cap != cap || ancien.couleur != couleur;
}
