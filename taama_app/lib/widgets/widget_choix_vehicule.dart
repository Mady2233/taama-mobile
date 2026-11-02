import 'package:flutter/material.dart';
import '../models/service_course.dart';
import '../theme/couleurs_taama.dart';

/// Bottom sheet style DiDi : affiche les services disponibles (catalogue
/// TypeService) avec leur devis figé côté serveur, AVANT que le client
/// confirme la demande. Plus aucun prix calculé ici : chaque carte affiche
/// exactement le `prix`/`devisId` reçus de POST /trajets/estimer/ (voir
/// ApiService.estimerCourse) — le choix du client renvoie ce devis tel quel,
/// jamais un montant recalculé côté app.
Future<Map<String, dynamic>?> afficherChoixVehicule(
  BuildContext context, {
  required String destination,
  required double distanceKm,
  String? typePreselectionne,
  required List<ServiceCourse> services,
}) async {
  // typePreselectionne ('Voiture'/'Moto', ex. depuis l'écran Services) filtre
  // la liste plutôt que de sauter le choix : le client voit toujours le prix
  // RÉEL avant de confirmer, jamais un choix auto-validé sur un devis qu'il
  // n'a pas vu. 'MOTO' est le seul type_vehicule qui vaut 'Moto' côté
  // backend (type_transport_associe) — tout le reste vaut 'Voiture'.
  final base = typePreselectionne == null
      ? services
      : services.where((s) =>
          (s.typeVehicule == 'MOTO') == (typePreselectionne == 'Moto')).toList();

  int parPrix(ServiceCourse a, ServiceCourse b) => (a.prix ?? 0).compareTo(b.prix ?? 0);
  final disponibles = base.where((s) => s.disponible && s.devisId != null).toList()..sort(parPrix);
  final sansChauffeur = base.where((s) => !s.disponible && s.devisId != null).toList()..sort(parPrix);
  final nonCommandables = base.where((s) => s.devisId == null).toList();
  final servicesTries = [...disponibles, ...sansChauffeur, ...nonCommandables];
  // Le premier commandable pilote l'en-tête (temps estimé, majoration,
  // détail de prix) — les autres services partagent le même trajet/la même
  // majoration horaire, seule leur tarification propre diffère.
  final ServiceCourse? reference =
      disponibles.isNotEmpty ? disponibles.first : (sansChauffeur.isNotEmpty ? sansChauffeur.first : null);
  final majoration = reference?.detail?['raison_majoration'] as String?;

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      // isScrollControlled: true laisse le sheet grandir jusqu'à toute la
      // hauteur de l'écran, mais un contenu non scrollable déborde quand
      // même si les cartes de service (mode dynamique, plusieurs services)
      // ne tiennent pas — bandes jaune/noir en bas. ConstrainedBox +
      // SingleChildScrollView : le sheet peut défiler au lieu de déborder.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Text(
              'Vers $destination',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: CouleursTaama.indigo,
              ),
            ),
            Text(
              reference?.etaMinutes != null
                  ? '${distanceKm.toStringAsFixed(1)} km • ${reference!.etaMinutes} min estimé'
                  : '${distanceKm.toStringAsFixed(1)} km',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),

            // Badge majoration si heure de pointe
            if (majoration != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.access_time,
                      color: Colors.orange,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$majoration — tarif majoré',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Text(
              'Choisir un véhicule',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),

            if (servicesTries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Aucun service disponible pour ce trajet pour le moment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else ...[
              // Une carte par ServiceCourse (avec chauffeur proche d'abord,
              // puis sans chauffeur, puis non commandables grisés — voir
              // servicesTries plus haut).
              for (final service in servicesTries) ...[
                _CarteService(
                  service: service,
                  onTap: () {
                    if (service.devisId != null) {
                      Navigator.pop(context, {
                        'type_service': service.id,
                        'devis_id': service.devisId,
                        'prix_estime': service.prix,
                        'temps_minutes': service.etaMinutes,
                        'disponible': service.disponible,
                      });
                      return;
                    }

                    // Non commandable : propose un repli plutôt que de laisser
                    // le client face à une carte grisée sans issue.
                    final repli = trouverStandardDeRepli(servicesTries);
                    if (repli != null) {
                      showDialog(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text('${service.nom} indisponible'),
                          content: Text(
                            'Le service ${service.nom} n\'est pas encore proposé.\n\n'
                            'Commander ${repli.nom} à ${repli.prix} FCFA à la place ?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Annuler'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                // Ferme d'abord le dialog (son propre
                                // context), PUIS le sheet (context du
                                // builder ci-dessus) — jamais l'inverse,
                                // sinon le dialog resterait affiché sur un
                                // sheet déjà fermé.
                                Navigator.pop(dialogContext);
                                Navigator.pop(context, {
                                  'type_service': repli.id,
                                  'devis_id': repli.devisId,
                                  'prix_estime': repli.prix,
                                  'temps_minutes': repli.etaMinutes,
                                  'disponible': repli.disponible,
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: CouleursTaama.terreCuite,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Commander'),
                            ),
                          ],
                        ),
                      );
                    } else {
                      showDialog(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Indisponible'),
                          content: const Text(
                            'Ce service n\'est pas encore proposé.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
            const SizedBox(height: 12),

            // Détail du prix (transparence totale)
            if (reference?.detail != null)
              GestureDetector(
                onTap: () => _afficherDetailPrix(context, reference!.detail!),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Comment est calculé le prix ?',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// Détail tel que renvoyé par calculer_prix_service (backend) : pas de
/// ventilation base/distance/temps (ce moteur n'a pas de terme temps,
/// contrairement à l'ancien calculer_prix) — seuls distance, majoration
/// éventuelle et prix final sont disponibles. Jamais de ligne inventée pour
/// combler l'absence d'un sous-total que le serveur ne fournit pas.
void _afficherDetailPrix(BuildContext context, Map<String, dynamic> detail) {
  final raisonMajoration = detail['raison_majoration'] as String?;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: const Text(
        'Détail du prix 🚗',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LignePrix('Distance', '${detail['distance_km']} km'),
            if (raisonMajoration != null)
              _LignePrix(
                raisonMajoration,
                '×${detail['coefficient']}',
                couleur: Colors.orange,
              ),
            const Divider(),
            _LignePrix(
              'TOTAL',
              '${detail['prix_final']} FCFA',
              gras: true,
              couleur: CouleursTaama.terreCuite,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

class _LignePrix extends StatelessWidget {
  final String label;
  final String valeur;
  final bool gras;
  final Color? couleur;

  const _LignePrix(this.label, this.valeur, {this.gras = false, this.couleur});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: gras ? FontWeight.bold : FontWeight.normal,
              color: couleur,
            ),
          ),
          Text(
            valeur,
            style: TextStyle(
              fontWeight: gras ? FontWeight.bold : FontWeight.normal,
              color: couleur ?? CouleursTaama.indigo,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconePourTypeVehicule(String typeVehicule) {
  switch (typeVehicule) {
    case 'MOTO':
      return Icons.two_wheeler;
    case 'BERLINE':
      return Icons.directions_car;
    case '4X4':
      return Icons.directions_car;
    case 'TRICYCLE':
      return Icons.electric_rickshaw;
    default:
      return Icons.directions_car;
  }
}

Color _couleurPourService(ServiceCourse service) {
  if (service.necessiteClimatisation) return CouleursTaama.or;
  return service.typeVehicule == 'MOTO'
      ? CouleursTaama.terreCuite
      : CouleursTaama.indigo;
}

/// Carte MODE DYNAMIQUE — un service (ServiceCourse) du catalogue. Même
/// style visuel que _CarteVehicule (fond/bordure alpha, radius 14) sans
/// modifier ce dernier, qui reste utilisé par le mode statique.
///
/// Toujours tappable (jamais onTap: null), même indisponible — c'est ce tap
/// qui déclenche la proposition de repli (voir l'appelant).
class _CarteService extends StatelessWidget {
  final ServiceCourse service;
  final VoidCallback onTap;

  const _CarteService({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final couleur = _couleurPourService(service);
    final icone = _iconePourTypeVehicule(service.typeVehicule);

    final carte = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: couleur.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icone, size: 32, color: couleur),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          service.nom,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: couleur,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (service.necessiteClimatisation) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: CouleursTaama.or.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.ac_unit,
                                size: 11,
                                color: CouleursTaama.or,
                              ),
                              const SizedBox(width: 2),
                              const Text(
                                'Climatisé',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: CouleursTaama.or,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Pas de ligne (ni SizedBox, ni Text vide) si la
                  // description est vide — évite un espace mort dans la mise
                  // en page.
                  if (service.description.isNotEmpty)
                    Text(
                      service.description,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  if (service.disponible && service.etaMinutes != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${service.etaMinutes} min',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    )
                  else if (service.devisId != null)
                    Text(
                      'Recherche à la commande',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (service.devisId != null && service.prix != null)
                  Text(
                    '${service.prix} FCFA',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: couleur,
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Indisponible',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (service.devisId != null)
                  const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              ],
            ),
          ],
        ),
      ),
    );

    // Non commandable : opacité réduite, mais PAS IgnorePointer/AbsorbPointer —
    // la carte doit rester tappable (déclenche le repli).
    return service.devisId != null ? carte : Opacity(opacity: 0.5, child: carte);
  }
}
