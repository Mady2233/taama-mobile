// Vérification d'identité du client, FACULTATIVE : rien dans la recherche ni
// la commande n'en dépend. Lecture défensive : un statut inconnu n'est jamais
// remplacé par un statut deviné.

enum StatutIdentite { nonSoumis, enAttente, approuve, refuse }

/// Statut envoyé par le serveur (`non_soumis`, `en_attente`, `approuve`,
/// `refuse`), null s'il est absent ou inconnu.
StatutIdentite? statutIdentiteDepuis(Object? brut) => switch (brut) {
      'non_soumis' => StatutIdentite.nonSoumis,
      'en_attente' => StatutIdentite.enAttente,
      'approuve' => StatutIdentite.approuve,
      'refuse' => StatutIdentite.refuse,
      _ => null,
    };

class VerificationIdentite {
  const VerificationIdentite({required this.statut, this.motifRefus});

  final StatutIdentite statut;

  /// Seulement pour une pièce refusée : ce que le client doit corriger.
  final String? motifRefus;

  bool get peutEnvoyer => statut != StatutIdentite.approuve;

  static VerificationIdentite? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final statut = statutIdentiteDepuis(brut['statut']);
    if (statut == null) return null;
    final motif = brut['motif_refus']?.toString().trim() ?? '';
    return VerificationIdentite(
      statut: statut,
      motifRefus: statut == StatutIdentite.refuse && motif.isNotEmpty ? motif : null,
    );
  }
}
