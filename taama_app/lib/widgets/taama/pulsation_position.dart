// lib/widgets/taama/pulsation_position.dart
//
// Point « vous êtes ici » avec deux ondes décalées.

import 'package:flutter/material.dart';

import '../../theme/taama_theme.dart';
import 'anime_en_boucle.dart';

class PulsationPosition extends StatelessWidget {
  const PulsationPosition({
    super.key,
    this.couleur = TaamaColors.primary,
    this.taille = 72,
  });

  final Color couleur;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final point = Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: TaamaShadows.card,
      ),
    );

    return Semantics(
      label: 'Votre position',
      child: SizedBox(
        width: taille,
        height: taille,
        child: AnimeEnBoucle(
          duree: const Duration(milliseconds: 2400),
          allerRetour: false,
          courbe: Curves.linear,
          child: point,
          builder: (context, t, child) => Stack(
            alignment: Alignment.center,
            children: [
              _onde(t),
              _onde((t + 0.5) % 1),
              child!,
            ],
          ),
        ),
      ),
    );
  }

  Widget _onde(double t) {
    final diametre = taille * (0.3 + 0.7 * Curves.easeOut.transform(t));
    return Opacity(
      opacity: (1 - t) * 0.7,
      child: Container(
        width: diametre,
        height: diametre,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: couleur.withValues(alpha: 0.10),
          border: Border.all(color: couleur, width: 2),
        ),
      ),
    );
  }
}
