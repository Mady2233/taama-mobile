import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../chauffeur_proche.dart';
import '../couleurs_recherche.dart';
import 'avatar_chauffeur.dart';

/// Radar des chauffeurs : anneaux de distance, balayage animé et marqueurs
/// placés à leur position réelle relative au client (projection locale,
/// exacte à l'échelle de quelques kilomètres).
class RadarChauffeurs extends StatefulWidget {
  const RadarChauffeurs({
    super.key,
    required this.chauffeurs,
    required this.filtre,
    required this.selectionne,
    required this.centre,
    required this.rayonM,
    required this.onSelection,
  }) : assert(rayonM > 0);

  /// Tous les chauffeurs : ceux qui ne passent pas le filtre s'estompent.
  final List<ChauffeurProche> chauffeurs;
  final TypeVehicule? filtre;
  final ChauffeurProche? selectionne;
  final GeoPoint centre;
  final int rayonM;
  final ValueChanged<ChauffeurProche> onSelection;

  @override
  State<RadarChauffeurs> createState() => _RadarChauffeursState();
}

class _RadarChauffeursState extends State<RadarChauffeurs>
    with SingleTickerProviderStateMixin {
  static const _anneaux = 3;
  static const _cible = 56.0; // zone tactile d'un marqueur
  static const _marge = 22.0; // garde les marqueurs dans le cadre
  static const _deplacement = Duration(milliseconds: 900);

  late final AnimationController _balayage = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respecte le réglage système « réduire les animations ».
    if (MediaQuery.of(context).disableAnimations) {
      _balayage
        ..stop()
        ..value = 0;
    } else if (!_balayage.isAnimating) {
      _balayage.repeat();
    }
  }

  @override
  void dispose() {
    _balayage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Radar des chauffeurs dans un rayon de '
          '${formaterRayon(widget.rayonM)}',
      child: LayoutBuilder(
        builder: (context, contraintes) {
          final taille = contraintes.biggest;
          final centre = taille.center(Offset.zero);
          final rayonPx = math.max(0.0, taille.shortestSide / 2 - _marge);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PeintreRadar(
                      balayage: _balayage,
                      rayonPx: rayonPx,
                      anneaux: _anneaux,
                    ),
                  ),
                ),
              ),
              for (var i = 1; i < _anneaux; i++)
                Positioned(
                  left: centre.dx,
                  top: centre.dy + rayonPx * i / _anneaux,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -0.5),
                    child: _EtiquetteDistance(
                      texte: formaterRayon((widget.rayonM * i / _anneaux).round()),
                    ),
                  ),
                ),
              Positioned(
                left: centre.dx - 14,
                top: centre.dy - 14,
                width: 28,
                height: 28,
                child: const _PointClient(),
              ),
              ..._marqueurs(centre, rayonPx, taille.width),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _marqueurs(Offset centre, double rayonPx, double largeur) {
    final selection = widget.selectionne;
    final fond = <Widget>[];
    final devant = <Widget>[];

    for (final chauffeur in widget.chauffeurs) {
      final visible =
          widget.filtre == null || chauffeur.typeVehicule == widget.filtre;
      final estSelectionne = visible && chauffeur.id == selection?.id;
      final p = _projeter(chauffeur.position, centre, rayonPx);

      final marqueur = AnimatedPositioned(
        key: ValueKey('marqueur-${chauffeur.id}'),
        duration: _deplacement,
        curve: Curves.easeInOut,
        left: p.dx - _cible / 2,
        top: p.dy - _cible / 2,
        width: _cible,
        height: _cible,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: visible ? 1.0 : 0.0,
            child: _Marqueur(
              chauffeur: chauffeur,
              selectionne: estSelectionne,
              onTap: () => widget.onSelection(chauffeur),
            ),
          ),
        ),
      );

      if (estSelectionne) {
        // Le sélectionné passe au premier plan, avec sa bulle.
        devant
          ..add(marqueur)
          ..add(AnimatedPositioned(
            key: const ValueKey('bulle'),
            duration: _deplacement,
            curve: Curves.easeInOut,
            left: p.dx,
            top: p.dy - 30,
            child: FractionalTranslation(
              translation: Offset(_decalageBulle(p.dx / largeur), -1),
              child: IgnorePointer(child: _Bulle(chauffeur: chauffeur)),
            ),
          ));
      } else {
        fond.add(marqueur);
      }
    }
    return [...fond, ...devant];
  }

  Offset _projeter(GeoPoint point, Offset centre, double rayonPx) {
    final origine = widget.centre;
    final cosLat = math.cos(origine.lat * math.pi / 180);
    final est = (point.lng - origine.lng) * 111320 * cosLat;
    final nord = (point.lat - origine.lat) * 110540;
    var v = Offset(est, -nord) * (rayonPx / widget.rayonM);
    final d = v.distance;
    // Un chauffeur légèrement hors rayon reste posé sur l'anneau extérieur.
    if (d > rayonPx && d > 0) v = v * (rayonPx / d);
    return centre + v;
  }

  /// Évite que la bulle sorte de l'écran près des bords.
  static double _decalageBulle(double fraction) {
    if (fraction < 0.28) return -0.18;
    if (fraction > 0.72) return -0.82;
    return -0.5;
  }
}

class _Marqueur extends StatelessWidget {
  const _Marqueur({
    required this.chauffeur,
    required this.selectionne,
    required this.onTap,
  });

  final ChauffeurProche chauffeur;
  final bool selectionne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final estMoto = chauffeur.typeVehicule == TypeVehicule.moto;
    final couleur = CouleursRecherche.vehicule(chauffeur.typeVehicule);
    return Semantics(
      button: true,
      selected: selectionne,
      label: '${chauffeur.nomAffiche}, ${estMoto ? 'moto' : 'voiture'}, '
          '${chauffeur.etaMin} min',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedScale(
            scale: selectionne ? 1.0 : 0.74,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selectionne
                    ? const Color(0x2EFFFFFF)
                    : const Color(0x00FFFFFF),
                border: Border.all(
                  color: selectionne
                      ? const Color(0x40FFFFFF)
                      : const Color(0x00FFFFFF),
                ),
              ),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: couleur,
                  border: Border.all(
                    color: estMoto
                        ? CouleursRecherche.nuit
                        : const Color(0xD9FFFFFF),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: couleur.withAlpha(selectionne ? 150 : 70),
                      blurRadius: selectionne ? 18 : 8,
                    ),
                  ],
                ),
                child: Icon(
                  estMoto ? Icons.two_wheeler : Icons.directions_car_filled,
                  size: 22,
                  color: estMoto ? CouleursRecherche.nuit : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.chauffeur});

  final ChauffeurProche chauffeur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x4D000000), blurRadius: 14, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarChauffeur(chauffeur: chauffeur, taille: 26, badge: false),
          const SizedBox(width: 8),
          Text(
            chauffeur.prenom,
            maxLines: 1,
            style: const TextStyle(
              color: CouleursRecherche.texte,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${chauffeur.etaMin} min',
            maxLines: 1,
            style: const TextStyle(
              color: CouleursRecherche.indigo,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PointClient extends StatelessWidget {
  const _PointClient();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x995546E8), blurRadius: 16, spreadRadius: 3),
        ],
      ),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CouleursRecherche.indigo,
        ),
      ),
    );
  }
}

class _EtiquetteDistance extends StatelessWidget {
  const _EtiquetteDistance({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC0F1330),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          texte,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PeintreRadar extends CustomPainter {
  _PeintreRadar({
    required this.balayage,
    required this.rayonPx,
    required this.anneaux,
  }) : super(repaint: balayage);

  final Animation<double> balayage;
  final double rayonPx;
  final int anneaux;

  static const _ouverture = math.pi / 2.2; // ~80°

  @override
  void paint(Canvas canvas, Size size) {
    if (rayonPx <= 0) return;
    final centre = size.center(Offset.zero);
    final disque = Rect.fromCircle(center: centre, radius: rayonPx);

    canvas.drawCircle(
      centre,
      rayonPx,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x2E5546E8), Color(0x0F5546E8)],
        ).createShader(disque),
    );

    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= anneaux; i++) {
      trait.color =
          i == anneaux ? const Color(0x40FFFFFF) : const Color(0x24FFFFFF);
      canvas.drawCircle(centre, rayonPx * i / anneaux, trait);
    }

    // Secteur de balayage : bord d'attaque à midi pour la valeur 0,
    // rotation dans le sens horaire.
    final angle = -math.pi / 2 - _ouverture + balayage.value * 2 * math.pi;
    canvas
      ..save()
      ..translate(centre.dx, centre.dy)
      ..rotate(angle);
    final local = Rect.fromCircle(center: Offset.zero, radius: rayonPx);
    final secteur = Path()
      ..moveTo(0, 0)
      ..arcTo(local, 0, _ouverture, false)
      ..close();
    canvas
      ..drawPath(
        secteur,
        Paint()
          ..shader = const SweepGradient(
            endAngle: _ouverture,
            colors: [Color(0x00FFFFFF), Color(0x33FFFFFF)],
          ).createShader(local),
      )
      ..drawLine(
        Offset.zero,
        Offset(math.cos(_ouverture) * rayonPx, math.sin(_ouverture) * rayonPx),
        Paint()
          ..color = const Color(0x66FFFFFF)
          ..strokeWidth = 1.5,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _PeintreRadar ancien) =>
      ancien.rayonPx != rayonPx ||
      ancien.anneaux != anneaux ||
      ancien.balayage != balayage;
}
