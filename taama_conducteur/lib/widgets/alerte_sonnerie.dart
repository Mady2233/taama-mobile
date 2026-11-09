// lib/widgets/alerte_sonnerie.dart
//
// Accueil chauffeur, en ligne : ce qui empêcherait une demande de sonner, et
// un bouton « Régler » pour chaque point. Présentationnel : problèmes et
// action par paramètres (VerificationSonnerie dans l'écran).

import 'package:flutter/material.dart';

import '../services/verification_sonnerie.dart';
import '../theme/couleurs_taama.dart';

class AlerteSonnerie extends StatelessWidget {
  const AlerteSonnerie({super.key, required this.problemes, required this.onRegler});

  final List<ProblemeSonnerie> problemes;
  final ValueChanged<ProblemeSonnerie> onRegler;

  static (IconData, String, String) _texte(ProblemeSonnerie probleme) => switch (probleme) {
        ProblemeSonnerie.notificationsCoupees => (
            Icons.notifications_off_rounded,
            'Notifications coupées',
            'Active les notifications des demandes de course.',
          ),
        ProblemeSonnerie.sonnerieMuette => (
            Icons.volume_off_rounded,
            'Silencieux ou vibreur',
            'Monte le volume de la sonnerie du téléphone.',
          ),
        ProblemeSonnerie.economieBatterie => (
            Icons.battery_alert_rounded,
            'Économie de batterie',
            'Choisis « Ne pas optimiser » ou « Aucune restriction » pour Taama Conducteur.',
          ),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      decoration: BoxDecoration(
        color: CouleursTaama.blanc,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CouleursTaama.terreCuite.withValues(alpha: 0.35), width: 1.5),
        boxShadow: const [BoxShadow(color: CouleursTaama.ombreLegere, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CouleursTaama.terreCuite.withValues(alpha: 0.12),
                ),
                child: const Icon(Icons.ring_volume_rounded, size: 20, color: CouleursTaama.terreCuite),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Ton téléphone risque de ne pas sonner',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: CouleursTaama.indigo),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final probleme in problemes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(_texte(probleme).$1, size: 20, color: CouleursTaama.grisTexte),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _texte(probleme).$2,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: CouleursTaama.indigo),
                        ),
                        Text(
                          _texte(probleme).$3,
                          style: const TextStyle(fontSize: 12.5, height: 1.3, color: CouleursTaama.grisTexte),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => onRegler(probleme),
                    style: TextButton.styleFrom(
                      foregroundColor: CouleursTaama.terreCuite,
                      minimumSize: const Size(0, 44),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    child: const Text('Régler'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
