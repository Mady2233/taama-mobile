import 'package:flutter/material.dart';

/// Les types de véhicule disponibles pour le covoiturage à Bamako.
class TypeVehicule {
  final String nom;
  final IconData icone;
  final String description;

  const TypeVehicule({
    required this.nom,
    required this.icone,
    required this.description,
  });

  static List<TypeVehicule> tous() {
    return const [
      TypeVehicule(
        nom: 'Voiture',
        icone: Icons.directions_car,
        description: 'Trajet en voiture, plus confortable',
      ),
      TypeVehicule(
        nom: 'Moto',
        icone: Icons.two_wheeler,
        description: 'Trajet en moto, plus rapide en circulation',
      ),
    ];
  }
}