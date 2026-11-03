// Confirmation d'annulation d'une course par le client : motif obligatoire, et
// conditions lues sur le serveur (temps gratuit restant, montant). Jamais de délai
// ni de montant calculés ici : seul le serveur décide de ce qui est prélevé.

import 'package:flutter/material.dart';

import '../theme/taama_theme.dart';
import '../utils/format.dart';

/// Annulation.MOTIF_CHOICES_CLIENT (backend).
const Map<String, String> motifsAnnulationClient = {
  'PLUS_BESOIN': 'Je n’ai plus besoin du trajet',
  'ATTENTE_TROP_LONGUE': 'Attente trop longue',
  'ERREUR_ADRESSE': 'Erreur d’adresse',
  'PRIX_TROP_ELEVE': 'Prix trop élevé',
  'CONDUCTEUR_NE_VIENT_PAS': 'Le chauffeur ne vient pas',
  'CONDUCTEUR_INJOIGNABLE': 'Le chauffeur est injoignable',
  'AUTRE': 'Autre',
};

/// Annulation.MOTIFS_CLIENT_SANS_PENALITE (backend) : pour l'affichage, le serveur
/// reste seul à décider.
const Set<String> motifsSansPenalite = {'CONDUCTEUR_NE_VIENT_PAS', 'CONDUCTEUR_INJOIGNABLE'};

/// Conditions affichées. [secondesGratuites] : null tant que personne n'a accepté.
/// Null en retour : rien à annoncer (mode gratuit, délai dépassé).
String? conditionsAnnulation({
  required int? secondesGratuites,
  required int penaliteTardive,
  required String? motif,
}) {
  if (secondesGratuites == null) return 'Annulation gratuite.';
  if (secondesGratuites > 0) {
    final minutes = (secondesGratuites / 60).ceil();
    return 'Annulation gratuite encore $minutes min.';
  }
  if (penaliteTardive <= 0) return null;
  if (motif != null && motifsSansPenalite.contains(motif)) {
    return 'Annulation gratuite : le chauffeur est en cause.';
  }
  return 'Une pénalité de ${formaterFcfa(penaliteTardive)} s’applique, '
      'sauf si le chauffeur est en cause.';
}

/// Le motif choisi, ou null si le client garde sa course.
Future<String?> afficherDialogueAnnulationCourse(
  BuildContext context, {
  required int? secondesGratuites,
  required int penaliteTardive,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _DialogueAnnulationCourse(
      secondesGratuites: secondesGratuites,
      penaliteTardive: penaliteTardive,
    ),
  );
}

class _DialogueAnnulationCourse extends StatefulWidget {
  const _DialogueAnnulationCourse({
    required this.secondesGratuites,
    required this.penaliteTardive,
  });

  final int? secondesGratuites;
  final int penaliteTardive;

  @override
  State<_DialogueAnnulationCourse> createState() => _DialogueAnnulationCourseState();
}

class _DialogueAnnulationCourseState extends State<_DialogueAnnulationCourse> {
  String? _motif;

  @override
  Widget build(BuildContext context) {
    final conditions = conditionsAnnulation(
      secondesGratuites: widget.secondesGratuites,
      penaliteTardive: widget.penaliteTardive,
      motif: _motif,
    );

    return AlertDialog(
      title: const Text('Annuler la course ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (conditions != null) ...[
              Text(conditions, style: TaamaText.body.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: TaamaSpacing.md),
            ],
            Text('Pourquoi ?', style: TaamaText.body.copyWith(color: TaamaColors.textSecondary)),
            const SizedBox(height: 4),
            for (final entree in motifsAnnulationClient.entries)
              InkWell(
                onTap: () => setState(() => _motif = entree.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        _motif == entree.key
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: _motif == entree.key
                            ? TaamaColors.primary
                            : TaamaColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(entree.value, style: TaamaText.body)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Garder la course'),
        ),
        TextButton(
          onPressed: _motif == null ? null : () => Navigator.pop(context, _motif),
          style: TextButton.styleFrom(foregroundColor: TaamaColors.danger),
          child: const Text('Annuler la course'),
        ),
      ],
    );
  }
}
