// lib/widgets/taama/marque_taama.dart
//
// Éléments de marque des écrans d'entrée (démarrage, présentation,
// connexion) : logo, nom « taama », fond bleu nuit et promesses. Couleurs et
// polices de taama_theme.dart uniquement.

import 'package:flutter/material.dart';

import '../../theme/taama_theme.dart';

/// Logo : le trajet de Taama (deux points reliés par une courbe) sur une
/// pastille violette.
class LogoTaama extends StatelessWidget {
  const LogoTaama({super.key, this.taille = 96});

  final double taille;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(taille * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [TaamaColors.routeNight, TaamaColors.primary],
        ),
        border: Border.all(color: TaamaColors.textOnDark.withValues(alpha: 0.22), width: 1.5),
        boxShadow: const [
          BoxShadow(color: TaamaColors.ombreMarqueur, blurRadius: 28, offset: Offset(0, 12)),
        ],
      ),
      child: CustomPaint(painter: _TrajetPainter()),
    );
  }
}

class _TrajetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 512;
    final sy = size.height / 512;
    final trait = Paint()
      ..color = TaamaColors.textOnDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30 * sx
      ..strokeCap = StrokeCap.round;
    final trajet = Path()
      ..moveTo(118 * sx, 220 * sy)
      ..cubicTo(136 * sx, 270 * sy, 204 * sx, 290 * sy, 256 * sx, 338 * sy)
      ..cubicTo(308 * sx, 290 * sy, 376 * sx, 270 * sy, 394 * sx, 220 * sy);
    canvas.drawPath(trajet, trait);
    final point = Paint()..color = TaamaColors.textOnDark;
    canvas.drawCircle(Offset(118 * sx, 220 * sy), 30 * sx, point);
    canvas.drawCircle(Offset(394 * sx, 220 * sy), 30 * sx, point);
    canvas.drawCircle(Offset(256 * sx, 338 * sy), 26 * sx, Paint()..color = TaamaColors.accentMint);
  }

  @override
  bool shouldRepaint(_TrajetPainter oldDelegate) => false;
}

/// « taama » en Sora.
class NomTaama extends StatelessWidget {
  const NomTaama({super.key, this.taille = 44});

  final double taille;

  @override
  Widget build(BuildContext context) {
    return Text(
      'taama',
      style: TaamaText.title.copyWith(
        fontSize: taille,
        fontWeight: FontWeight.w800,
        color: TaamaColors.textOnDark,
        letterSpacing: -taille * 0.04,
        height: 1.05,
      ),
    );
  }
}

/// Fond bleu nuit des écrans d'entrée, avec deux halos de lumière.
class FondMarque extends StatelessWidget {
  const FondMarque({super.key, required this.child, this.intensite = 1});

  final Widget child;

  /// 0 à 1 : apparition progressive (écran de démarrage).
  final double intensite;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [TaamaColors.navyLight, TaamaColors.navy],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -100,
            child: _Halo(taille: 320, couleur: TaamaColors.routeNight, opacite: 0.28 * intensite),
          ),
          Positioned(
            bottom: -140,
            left: -120,
            child: _Halo(taille: 340, couleur: TaamaColors.accentMint, opacite: 0.12 * intensite),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.taille, required this.couleur, required this.opacite});

  final double taille;
  final Color couleur;
  final double opacite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [couleur.withValues(alpha: opacite), couleur.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// Ce que Taama garantit vraiment (jamais de chiffre inventé).
const List<(IconData, String)> promessesTaama = [
  (Icons.sell_rounded, 'Prix annoncé avant la course'),
  (Icons.verified_user_rounded, 'Chauffeurs vérifiés'),
  (Icons.near_me_rounded, 'Suivi en direct'),
];

class PastillePromesse extends StatelessWidget {
  const PastillePromesse({super.key, required this.icone, required this.texte});

  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: TaamaColors.textOnDark.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(TaamaRadius.pill),
        border: Border.all(color: TaamaColors.textOnDark.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 15, color: TaamaColors.accentMint),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texte,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TaamaText.body.copyWith(fontSize: 12.5, color: TaamaColors.textOnDark),
            ),
          ),
        ],
      ),
    );
  }
}
