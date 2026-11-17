// lib/widgets/vehicule_vu_dessus.dart
//
// Voiture ou moto vue de dessus, dessinée en code (nette à tout zoom, aucune
// image à charger), tournée vers [cap]. Dessins propres à Taama, mêmes que
// dans l'app client (taama_app/lib/widgets/taama/vehicule_vu_dessus.dart) :
// ici, le véhicule du chauffeur sur son accueil.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../theme/couleurs_taama.dart';

class VehiculeVuDessus extends StatelessWidget {
  const VehiculeVuDessus({
    super.key,
    required this.estMoto,
    this.cap = 0,
    this.taille = 44,
    this.miseEnAvant = false,
  });

  final bool estMoto;

  /// Direction, en radians depuis le nord (sens horaire).
  final double cap;

  /// Côté du carré qui contient le véhicule (sa longueur, à peu près).
  final double taille;

  /// Véhicule de la course en cours, ou chauffeur choisi : couleur d'accent.
  final bool miseEnAvant;

  @override
  Widget build(BuildContext context) {
    final carrosserie = miseEnAvant ? CouleursTaama.terreCuite : CouleursTaama.indigo;
    return SizedBox.square(
      dimension: taille,
      child: Transform.rotate(
        angle: cap,
        child: CustomPaint(
          painter: estMoto
              ? _Moto(carrosserie: carrosserie)
              : _Voiture(carrosserie: carrosserie),
        ),
      ),
    );
  }
}

/// Direction en radians (depuis le nord, sens horaire) de [a] vers [b].
double capEntre(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  return math.atan2(
    math.sin(dLng) * math.cos(lat2),
    math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng),
  );
}

/// Orientation d'un véhicule qui n'a pas encore bougé : fixe pour un même
/// pseudonyme (pas de pivot d'un rafraîchissement à l'autre), variée d'un
/// véhicule à l'autre.
double capInitial(String id) {
  var h = 0;
  for (final u in id.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return (h % 360) * math.pi / 180;
}

const Color _casque = Color(0xFFF59E0B);
const Color _vitre = Color(0xFFB9C6E8);
const Color _vitreSombre = Color(0xFF8EA0D2);
const Color _phare = Color(0xFFFFF4C2);
const Color _feu = Color(0xFFE5484D);
const Color _ombre = Color(0x40101828);
const Color _lisere = Color(0xFFFFFFFF);

class _Voiture extends CustomPainter {
  _Voiture({required this.carrosserie});

  final Color carrosserie;

  @override
  void paint(Canvas canvas, Size size) {
    final l = size.width * 0.46; // largeur de la voiture
    final h = size.height * 0.92; // longueur
    final x = (size.width - l) / 2;
    final y = (size.height - h) / 2;
    final corps = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, l, h), Radius.circular(l * 0.34));

    // Ombre portée, puis liseré blanc : la voiture se détache de toute carte.
    canvas.drawRRect(
      corps.shift(const Offset(0, 1.5)),
      Paint()
        ..color = _ombre
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawRRect(corps.inflate(1.2), Paint()..color = _lisere);
    canvas.drawRRect(corps, Paint()..color = carrosserie);

    // Rétroviseurs.
    final retro = Paint()..color = carrosserie;
    canvas.drawOval(Rect.fromCenter(center: Offset(x - l * 0.06, y + h * 0.33), width: l * 0.2, height: h * 0.07), retro);
    canvas.drawOval(Rect.fromCenter(center: Offset(x + l * 1.06, y + h * 0.33), width: l * 0.2, height: h * 0.07), retro);

    // Pare-brise (avant, en haut) et lunette arrière.
    final pareBrise = Path()
      ..moveTo(x + l * 0.14, y + h * 0.36)
      ..lineTo(x + l * 0.86, y + h * 0.36)
      ..lineTo(x + l * 0.76, y + h * 0.22)
      ..quadraticBezierTo(x + l * 0.5, y + h * 0.18, x + l * 0.24, y + h * 0.22)
      ..close();
    canvas.drawPath(pareBrise, Paint()..color = _vitre);
    final lunette = Path()
      ..moveTo(x + l * 0.17, y + h * 0.72)
      ..lineTo(x + l * 0.83, y + h * 0.72)
      ..lineTo(x + l * 0.75, y + h * 0.83)
      ..quadraticBezierTo(x + l * 0.5, y + h * 0.86, x + l * 0.25, y + h * 0.83)
      ..close();
    canvas.drawPath(lunette, Paint()..color = _vitreSombre);

    // Toit, un peu plus clair : le relief.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + l * 0.17, y + h * 0.39, l * 0.66, h * 0.3),
        Radius.circular(l * 0.14),
      ),
      Paint()..color = Color.lerp(carrosserie, Colors.white, 0.16)!,
    );

    // Phares et feux.
    final phare = Paint()..color = _phare;
    final feu = Paint()..color = _feu;
    for (final cote in [0.2, 0.8]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x + l * cote, y + h * 0.035), width: l * 0.22, height: h * 0.035), phare);
      canvas.drawOval(Rect.fromCenter(center: Offset(x + l * cote, y + h * 0.968), width: l * 0.22, height: h * 0.03), feu);
    }
  }

  @override
  bool shouldRepaint(_Voiture ancien) => ancien.carrosserie != carrosserie;
}

class _Moto extends CustomPainter {
  _Moto({required this.carrosserie});

  final Color carrosserie;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final h = size.height * 0.86;
    final y = (size.height - h) / 2;
    final l = size.width * 0.24; // largeur du corps

    final ombre = Paint()
      ..color = _ombre
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    final corps = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, y + h * 0.5), width: l, height: h * 0.84),
      Radius.circular(l / 2),
    );
    canvas.drawRRect(corps.shift(const Offset(0, 1.5)), ombre);

    // Roues (avant en haut, arrière en bas), liseré blanc compris.
    final roue = Paint()..color = const Color(0xFF1D2433);
    for (final (cy, hauteur) in [(y + h * 0.1, h * 0.2), (y + h * 0.9, h * 0.2)]) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: l * 0.62, height: hauteur),
        Radius.circular(l * 0.31),
      );
      canvas.drawRRect(r.inflate(1.2), Paint()..color = _lisere);
      canvas.drawRRect(r, roue);
    }

    canvas.drawRRect(corps.inflate(1.2), Paint()..color = _lisere);
    canvas.drawRRect(corps, Paint()..color = carrosserie);

    // Guidon et ses poignées.
    final guidon = Paint()
      ..color = const Color(0xFF1D2433)
      ..strokeWidth = math.max(1.6, size.width * 0.045)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - size.width * 0.19, y + h * 0.27), Offset(cx + size.width * 0.19, y + h * 0.27), guidon);
    canvas.drawCircle(Offset(cx, y + h * 0.16), l * 0.22, Paint()..color = _phare);

    // Pilote : épaules et casque.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, y + h * 0.5), width: size.width * 0.36, height: h * 0.17),
      Paint()..color = Color.lerp(carrosserie, Colors.white, 0.2)!,
    );
    canvas.drawCircle(Offset(cx, y + h * 0.45), size.width * 0.105, Paint()..color = _lisere);
    canvas.drawCircle(Offset(cx, y + h * 0.45), size.width * 0.08, Paint()..color = _casque);
    canvas.drawCircle(Offset(cx, y + h * 0.84), l * 0.2, Paint()..color = _feu);
  }

  @override
  bool shouldRepaint(_Moto ancien) => ancien.carrosserie != carrosserie;
}
