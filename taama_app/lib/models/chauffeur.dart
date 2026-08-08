/// Représente un chauffeur assigné à une course
///
/// Pour l'instant, les données sont fictives (en attendant le backend).
/// Plus tard, ces informations viendront de l'API après l'acceptation de la course.
class Chauffeur {
  final String nom;
  final String vehicule;
  final String plaque;
  final double note;

  const Chauffeur({
    required this.nom,
    required this.vehicule,
    required this.plaque,
    required this.note,
  });

  /// Génère un chauffeur fictif selon le type de transport choisi
  /// (Taxi -> chauffeur privé, Sotrama -> conducteur du véhicule de ligne)
  static Chauffeur genererPourType(String typeTransport) {
    switch (typeTransport) {
      case 'Sotrama':
        return const Chauffeur(
          nom: 'Oumar Traoré',
          vehicule: 'Sotrama - Ligne 12',
          plaque: 'BKO 4521',
          note: 4.5,
        );
      case 'Livraison':
        return const Chauffeur(
          nom: 'Ibrahim Coulibaly',
          vehicule: 'Moto - Livreur',
          plaque: 'BKO 7788',
          note: 4.8,
        );
      default: // Taxi
        return const Chauffeur(
          nom: 'Moussa Diarra',
          vehicule: 'Toyota Corolla - Gris',
          plaque: 'BKO 1234',
          note: 4.9,
        );
    }
  }
}