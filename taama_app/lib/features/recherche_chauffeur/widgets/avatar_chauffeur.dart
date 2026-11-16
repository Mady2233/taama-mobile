import 'package:flutter/material.dart';

import '../../../theme/taama_theme.dart';
import '../couleurs_recherche.dart';

/// Pastille aux initiales, avec badge du type de véhicule. Des valeurs
/// simples, pas un modèle : le radar (ChauffeurProche) et la carte d'accueil
/// (ConducteurProche) s'en servent tous les deux.
class AvatarChauffeur extends StatelessWidget {
  const AvatarChauffeur({
    super.key,
    required this.graine,
    required this.initiales,
    required this.estMoto,
    this.taille = 52,
    this.badge = true,
  });

  /// Pseudonyme du chauffeur : couleur stable d'un rafraîchissement à l'autre.
  final String graine;
  final String initiales;
  final bool estMoto;
  final double taille;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final tailleBadge = taille * 0.42;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: taille,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CouleursRecherche.avatar(graine),
                ),
                child: Center(
                  child: Text(
                    initiales,
                    textScaler: TextScaler.noScaling,
                    // Police explicite : sur la carte d'accueil, le texte
                    // n'hérite pas de celle de l'app.
                    style: TextStyle(
                      fontFamily: TaamaFonts.body,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: taille * 0.34,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ),
            if (badge)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: tailleBadge,
                  height: tailleBadge,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CouleursRecherche.vehiculeEstMoto(estMoto),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(
                    estMoto ? Icons.two_wheeler : Icons.directions_car_filled,
                    size: tailleBadge * 0.56,
                    color: estMoto ? CouleursRecherche.nuit : Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
