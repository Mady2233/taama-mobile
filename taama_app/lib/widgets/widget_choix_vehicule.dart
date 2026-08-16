import 'package:flutter/material.dart';
import '../models/service_course.dart';
import '../theme/couleurs_taama.dart';

/// Bottom sheet style DiDi : affiche les types de véhicules disponibles
/// avec leur prix estimé AVANT que le client confirme la demande.
///
/// Utilise le détail de prix calculé par le backend (`detailPrixVoiture` /
/// `detailPrixMoto`, tarification dynamique façon Uber) quand disponible,
/// sinon retombe sur une estimation locale approximative.
Future<Map<String, dynamic>?> afficherChoixVehicule(
  BuildContext context, {
  required String destination,
  required double distanceKm,
  String? typePreselectionne,
  Map<String, dynamic>? detailPrixVoiture,
  Map<String, dynamic>? detailPrixMoto,
  List<ServiceCourse>? services,
}) async {
  // Utilise les prix du backend si disponibles
  final prixVoiture = detailPrixVoiture?['prix_final'] as int? ??
      (distanceKm * 150 + 500).round().clamp(500, 999999);
  final prixMoto = detailPrixMoto?['prix_final'] as int? ??
      (distanceKm * 100 + 300).round().clamp(500, 999999);

  final tempsVoiture = detailPrixVoiture?['temps_minutes'] as num? ??
      (distanceKm / 20 * 60).round();
  final tempsMoto = detailPrixMoto?['temps_minutes'] as num? ??
      (distanceKm / 25 * 60).round();

  final majorationVoiture = detailPrixVoiture?['raison_majoration'] as String?;

  // Si le véhicule a déjà été choisi en amont (ex : depuis l'écran Services),
  // on saute le choix manuel et on renvoie directement l'estimation correspondante.
  if (typePreselectionne != null) {
    if (typePreselectionne == 'Moto') {
      return {
        'type': 'Moto',
        'prix_estime': prixMoto,
        'temps_minutes': tempsMoto,
      };
    }
    return {
      'type': 'Voiture',
      'prix_estime': prixVoiture,
      'temps_minutes': tempsVoiture,
    };
  }

  // MODE DYNAMIQUE (piloté par le catalogue TypeService/estimer_course) si
  // services est fourni et non vide, sinon MODE STATIQUE ci-dessous
  // (2 cartes Flex/Moto en dur, comportement historique inchangé).
  final bool modeDynamique = services != null && services.isNotEmpty;
  final List<ServiceCourse> servicesTries = modeDynamique
      ? (() {
          final disponibles = services.where((s) => s.disponible).toList()
            ..sort((a, b) => (a.prix ?? 0).compareTo(b.prix ?? 0));
          final indisponibles = services.where((s) => !s.disponible).toList();
          return [...disponibles, ...indisponibles];
        })()
      : const <ServiceCourse>[];

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text('Vers $destination',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: CouleursTaama.indigo)),
          Text('${distanceKm.toStringAsFixed(1)} km • ${tempsVoiture.round()} min estimé',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),

          // Badge majoration si heure de pointe
          if (majorationVoiture != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time,
                      color: Colors.orange, size: 14),
                  const SizedBox(width: 4),
                  Text('$majorationVoiture — tarif majoré',
                      style: const TextStyle(
                          color: Colors.orange, fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Text('Choisir un véhicule',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 12),

          if (modeDynamique) ...[
            // MODE DYNAMIQUE : une carte par ServiceCourse (disponibles
            // triés par prix croissant en premier, indisponibles grisés
            // ensuite — voir servicesTries plus haut).
            for (final service in servicesTries) ...[
              _CarteService(
                service: service,
                onTap: () {
                  if (service.disponible) {
                    Navigator.pop(context, {
                      'type_service': service.id,
                      'prix_estime': service.prix,
                      'temps_minutes': service.etaMinutes,
                    });
                    return;
                  }

                  // Indisponible : propose un repli plutôt que de laisser
                  // le client face à une carte grisée sans issue.
                  final repli = trouverStandardDeRepli(servicesTries);
                  if (repli != null) {
                    showDialog(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text('Pas de ${service.nom} disponible'),
                        content: Text(
                          'Aucun ${service.nom} près de vous pour l\'instant.\n\n'
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
                                'prix_estime': repli.prix,
                                'temps_minutes': repli.etaMinutes,
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
                          'Aucune voiture disponible près de vous pour l\'instant.',
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
          ] else ...[
            // MODE STATIQUE (comportement historique, inchangé) : 2 cartes
            // en dur, prix locaux/backend-detail déjà calculés plus haut.
            _CarteVehicule(
              emoji: '🚗',
              label: 'Taama Flex',
              description: 'Confortable • 1-4 passagers',
              prix: prixVoiture,
              tempsAttente: '${tempsVoiture.round()} min',
              onTap: () => Navigator.pop(context, {
                'type': 'Voiture',
                'prix_estime': prixVoiture,
                'temps_minutes': tempsVoiture,
              }),
            ),
            const SizedBox(height: 10),

            _CarteVehicule(
              emoji: '🏍️',
              label: 'Taama Moto',
              description: 'Rapide • Évite les embouteillages',
              prix: prixMoto,
              tempsAttente: '${tempsMoto.round()} min',
              couleur: CouleursTaama.terreCuite,
              onTap: () => Navigator.pop(context, {
                'type': 'Moto',
                'prix_estime': prixMoto,
                'temps_minutes': tempsMoto,
              }),
            ),
          ],
          const SizedBox(height: 12),

          // Détail du prix (transparence totale)
          if (detailPrixVoiture != null)
            GestureDetector(
              onTap: () => _afficherDetailPrix(context, detailPrixVoiture),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text('Comment est calculé le prix ?',
                      style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                          decoration: TextDecoration.underline)),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _afficherDetailPrix(
    BuildContext context, Map<String, dynamic> detail) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: const Text('Détail du prix 🚗',
          style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LignePrix('Prix de base', '${detail['prix_base']} FCFA'),
            _LignePrix(
              'Distance (${detail['distance_km']} km)',
              '${detail['prix_distance']} FCFA',
            ),
            _LignePrix(
              'Temps (${detail['temps_minutes']} min)',
              '${detail['prix_temps']} FCFA',
            ),
            const Divider(),
            _LignePrix('Sous-total', '${detail['sous_total']} FCFA'),
            if (detail['raison_majoration'] != null)
              _LignePrix(
                '${detail['raison_majoration']} (×${detail['coefficient']})',
                '+${((detail['coefficient'] - 1) * detail['sous_total']).round()} FCFA',
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

  const _LignePrix(this.label, this.valeur,
      {this.gras = false, this.couleur});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: gras ? FontWeight.bold : FontWeight.normal,
                  color: couleur)),
          Text(valeur,
              style: TextStyle(
                  fontWeight: gras ? FontWeight.bold : FontWeight.normal,
                  color: couleur ?? CouleursTaama.indigo)),
        ],
      ),
    );
  }
}

class _CarteVehicule extends StatelessWidget {
  final String emoji, label, description, tempsAttente;
  final int prix;
  final Color couleur;
  final VoidCallback onTap;

  const _CarteVehicule({
    required this.emoji, required this.label,
    required this.description, required this.prix,
    required this.tempsAttente, required this.onTap,
    this.couleur = CouleursTaama.indigo,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: couleur)),
                  Text(description,
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12)),
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: 12, color: Colors.green),
                      const SizedBox(width: 3),
                      Text('$tempsAttente de trajet',
                          style: const TextStyle(
                              color: Colors.green, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$prix FCFA',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: couleur)),
                const Icon(Icons.chevron_right,
                    color: Colors.grey, size: 20),
              ],
            ),
          ],
        ),
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
                              color: couleur),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (service.necessiteClimatisation) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: CouleursTaama.or.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.ac_unit,
                                  size: 11, color: CouleursTaama.or),
                              const SizedBox(width: 2),
                              const Text('Climatisé',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: CouleursTaama.or,
                                      fontWeight: FontWeight.bold)),
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
                    Text(service.description,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12)),
                  if (service.disponible && service.etaMinutes != null)
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 12, color: Colors.green),
                        const SizedBox(width: 3),
                        Text('${service.etaMinutes} min',
                            style: const TextStyle(
                                color: Colors.green, fontSize: 11)),
                      ],
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (service.disponible && service.prix != null)
                  Text('${service.prix} FCFA',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: couleur))
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('Indisponible',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.bold)),
                  ),
                if (service.disponible)
                  const Icon(Icons.chevron_right,
                      color: Colors.grey, size: 20),
              ],
            ),
          ],
        ),
      ),
    );

    // Indisponible : opacité réduite, mais PAS IgnorePointer/AbsorbPointer —
    // la carte doit rester tappable (déclenche le repli).
    return service.disponible ? carte : Opacity(opacity: 0.5, child: carte);
  }
}
