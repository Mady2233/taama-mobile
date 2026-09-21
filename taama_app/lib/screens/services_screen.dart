// lib/screens/services_screen.dart
//
// Écran Services — aligné sur le système de design v3 (voir
// theme/taama_theme.dart et screens/home/home_screen.dart) : palette
// restreinte (navy/indigo, ambre réservé aux mises en avant), cartes
// blanches bordées, icônes Material plutôt qu'emoji, aucune valeur hex en
// dur. Course/Moto/Réserver passent maintenant par le même flux moderne
// (recherche de destination -> EcranDemandeInstantanee) qu'utilise déjà
// l'accueil v3, au lieu de l'ancien EcranCarte (supprimé, voir l'historique
// git).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/taama_theme.dart';
import 'courier_screen.dart';
import 'recherche_screen.dart';
import 'resultats_recherche_screen.dart';
import 'mes_demandes_planifiees_screen.dart';

class EcranServices extends StatelessWidget {
  const EcranServices({super.key});

  /// Recherche de destination puis création de la demande, avec un type de
  /// véhicule pré-sélectionné optionnel (null = laissé au choix sur l'écran
  /// suivant, comme "Réserver").
  Future<void> _choisirDestinationPuisDemander(
    BuildContext context,
    String? typePreselectionne,
  ) async {
    final resultat = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EcranRecherche()),
    );
    if (resultat != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EcranDemandeInstantanee(
            destination: resultat.toString(),
            typePreselectionne: typePreselectionne,
          ),
        ),
      );
    }
  }

  void _bientot(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: TaamaColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(TaamaRadius.xl)),
        ),
        padding: const EdgeInsets.all(TaamaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: TaamaColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.rocket_launch_rounded,
                  color: TaamaColors.primary, size: 28),
            ),
            const SizedBox(height: TaamaSpacing.md),
            const Text(
              'Bientôt disponible',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: TaamaColors.textPrimary,
              ),
            ),
            const SizedBox(height: TaamaSpacing.sm),
            Text(
              'Cette fonctionnalité arrive bientôt.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
            ),
            const SizedBox(height: TaamaSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Compris'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: TaamaColors.background,
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            const _EnTeteServices(),
            Padding(
              padding: const EdgeInsets.all(TaamaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _TitreSection(
                    icone: Icons.directions_car_filled_rounded,
                    titre: 'Transport',
                  ),
                  const SizedBox(height: TaamaSpacing.md),
                  _LigneServiceHub(
                    icone: Icons.directions_car_filled_rounded,
                    couleur: TaamaColors.primary,
                    titre: 'Course',
                    sousTitre: 'Voiture, à la demande',
                    onTap: () => _choisirDestinationPuisDemander(
                        context, 'Voiture'),
                  ),
                  const SizedBox(height: 10),
                  _LigneServiceHub(
                    icone: Icons.two_wheeler_rounded,
                    couleur: TaamaColors.navy,
                    titre: 'Moto',
                    sousTitre: 'Rapide, dans le trafic',
                    onTap: () =>
                        _choisirDestinationPuisDemander(context, 'Moto'),
                  ),
                  const SizedBox(height: 10),
                  _LigneServiceHub(
                    icone: Icons.inventory_2_rounded,
                    couleur: TaamaColors.warning,
                    fondIcone: TaamaColors.warningSoft,
                    titre: 'Courier',
                    sousTitre: 'Envoyer un colis',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const EcranCourier()),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LigneServiceHub(
                    icone: Icons.place_rounded,
                    couleur: TaamaColors.success,
                    fondIcone: TaamaColors.successSoft,
                    titre: 'Réserver',
                    sousTitre: 'Choisir une destination',
                    onTap: () => _choisirDestinationPuisDemander(context, null),
                  ),
                  const SizedBox(height: 10),
                  _LigneServiceHub(
                    icone: Icons.event_available_rounded,
                    couleur: TaamaColors.textPrimary,
                    fondIcone: TaamaColors.surfaceMuted,
                    titre: 'Planifier',
                    sousTitre: 'Réserver à l\'avance',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MesDemandesPlanifieesScreen()),
                    ),
                  ),

                  const SizedBox(height: TaamaSpacing.xl),

                  const _TitreSection(
                    icone: Icons.auto_awesome_rounded,
                    titre: 'Bientôt disponible',
                  ),
                  const SizedBox(height: TaamaSpacing.md),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.95,
                    children: [
                      _CarteBientot(
                          icone: Icons.woman_rounded,
                          label: 'Femmes',
                          onTap: () => _bientot(context)),
                      _CarteBientot(
                          icone: Icons.elderly_rounded,
                          label: 'Seniors',
                          onTap: () => _bientot(context)),
                      _CarteBientot(
                          icone: Icons.local_shipping_rounded,
                          label: 'Cargo',
                          onTap: () => _bientot(context)),
                      _CarteBientot(
                          icone: Icons.school_rounded,
                          label: 'Scolaire',
                          onTap: () => _bientot(context)),
                      _CarteBientot(
                          icone: Icons.medical_services_rounded,
                          label: 'Médical',
                          onTap: () => _bientot(context)),
                      _CarteBientot(
                          icone: Icons.flight_takeoff_rounded,
                          label: 'Aéroport',
                          onTap: () => _bientot(context)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── En-tête ───

class _EnTeteServices extends StatelessWidget {
  const _EnTeteServices();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: TaamaColors.navy,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + TaamaSpacing.md,
        left: TaamaSpacing.lg,
        right: TaamaSpacing.lg,
        bottom: TaamaSpacing.xl,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Services',
            style: TextStyle(
              color: TaamaColors.textOnDark,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Tout ce dont tu as besoin, à Bamako',
            style: TextStyle(color: TaamaColors.onNavyMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─── Titre de section ───

class _TitreSection extends StatelessWidget {
  const _TitreSection({required this.icone, required this.titre});

  final IconData icone;
  final String titre;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 18, color: TaamaColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          titre,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: TaamaColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ─── Carte de service (ligne) ───

class _LigneServiceHub extends StatelessWidget {
  const _LigneServiceHub({
    required this.icone,
    required this.couleur,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
    this.fondIcone,
  });

  final IconData icone;
  final Color couleur;
  final Color? fondIcone;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.surface,
      borderRadius: BorderRadius.circular(TaamaRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TaamaRadius.lg),
            border: Border.all(color: TaamaColors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: fondIcone ?? TaamaColors.primarySoft,
                  borderRadius: BorderRadius.circular(TaamaRadius.md),
                ),
                child: Icon(icone, size: 22, color: couleur),
              ),
              const SizedBox(width: TaamaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titre,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TaamaColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sousTitre,
                      style: const TextStyle(
                        fontSize: 12,
                        color: TaamaColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: TaamaColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Carte « bientôt disponible » ───

class _CarteBientot extends StatelessWidget {
  const _CarteBientot({
    required this.icone,
    required this.label,
    required this.onTap,
  });

  final IconData icone;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.surface,
      borderRadius: BorderRadius.circular(TaamaRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TaamaRadius.lg),
            border: Border.all(color: TaamaColors.border, width: 0.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 22, color: TaamaColors.textSecondary),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: TaamaColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
