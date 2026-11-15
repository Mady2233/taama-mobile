// lib/widgets/choix_mode_chauffeur.dart
//
// « Ton chauffeur » : le plus proche, ou le choisir sur la carte, au même
// prix. Seulement quand la feuille « Ton offre » n'est pas montrée (pas de
// négociation pour ce service) ; sinon ses deux boutons font ce choix.

import 'package:flutter/material.dart';

import '../theme/taama_theme.dart';
import '../utils/format.dart';

/// Vrai : choisir son chauffeur ; faux : le plus proche ; null : feuille
/// fermée, rien n'est commandé.
Future<bool?> afficherChoixModeChauffeur(BuildContext context, {required int? prix}) =>
    showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => FeuilleModeChauffeur(
        prix: prix,
        onChoix: (choisir) => Navigator.pop(context, choisir),
      ),
    );

class FeuilleModeChauffeur extends StatelessWidget {
  const FeuilleModeChauffeur({super.key, required this.prix, required this.onChoix});

  final int? prix;
  final ValueChanged<bool> onChoix;

  @override
  Widget build(BuildContext context) {
    final prix = this.prix;
    return Container(
      decoration: const BoxDecoration(
        color: TaamaColors.night,
        borderRadius: BorderRadius.vertical(top: Radius.circular(TaamaRadius.xl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(TaamaSpacing.lg, TaamaSpacing.lg, TaamaSpacing.lg, TaamaSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ton chauffeur', style: TaamaText.title.copyWith(fontSize: 20, color: TaamaColors.textOnDark)),
              const SizedBox(height: TaamaSpacing.xs),
              Text(
                'Le même prix dans les deux cas.',
                style: TaamaText.body.copyWith(fontSize: 13, color: TaamaColors.onNightMuted),
              ),
              const SizedBox(height: TaamaSpacing.lg),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: () => onChoix(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: TaamaColors.accentMint,
                    foregroundColor: TaamaColors.onAccentMint,
                    textStyle: TaamaText.body.copyWith(fontSize: 16.5, fontWeight: FontWeight.w800),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(prix == null ? 'Le plus proche' : 'Le plus proche · ${formaterFcfa(prix)}'),
                  ),
                ),
              ),
              const SizedBox(height: TaamaSpacing.sm),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () => onChoix(true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TaamaColors.textOnDark,
                    side: const BorderSide(color: TaamaColors.nightBorder),
                    textStyle: TaamaText.body.copyWith(fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Choisir mon chauffeur')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
