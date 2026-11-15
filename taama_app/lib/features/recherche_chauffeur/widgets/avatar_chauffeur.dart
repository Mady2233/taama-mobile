import 'package:flutter/material.dart';

import '../chauffeur_proche.dart';
import '../couleurs_recherche.dart';

/// Pastille aux initiales, avec badge du type de véhicule.
class AvatarChauffeur extends StatelessWidget {
  const AvatarChauffeur({
    super.key,
    required this.chauffeur,
    this.taille = 52,
    this.badge = true,
  });

  final ChauffeurProche chauffeur;
  final double taille;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final estMoto = chauffeur.typeVehicule == TypeVehicule.moto;
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
                  color: CouleursRecherche.avatar(chauffeur.id),
                ),
                child: Center(
                  child: Text(
                    chauffeur.initiales,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
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
                    color: CouleursRecherche.vehicule(chauffeur.typeVehicule),
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
