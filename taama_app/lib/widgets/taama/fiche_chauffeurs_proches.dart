// lib/widgets/taama/fiche_chauffeurs_proches.dart
//
// Fiche ouverte depuis une pastille de l'accueil : le ou les chauffeurs du
// groupe (prénom, note ou « Nouveau », véhicule, temps d'approche), sans
// aucun bouton de commande. Le choix du chauffeur vient après la destination
// et le prix : la fiche le rappelle.

import 'package:flutter/material.dart';

import '../../features/recherche_chauffeur/chauffeur_proche.dart'
    show formaterNote;
import '../../features/recherche_chauffeur/widgets/avatar_chauffeur.dart';
import '../../screens/home/home_models.dart';
import '../../theme/taama_theme.dart';

Future<void> afficherFicheChauffeursProches(
  BuildContext context, {
  required List<ConducteurProche> chauffeurs,
}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => FicheChauffeursProches(chauffeurs: chauffeurs),
    );

class FicheChauffeursProches extends StatelessWidget {
  const FicheChauffeursProches({super.key, required this.chauffeurs});

  final List<ConducteurProche> chauffeurs;

  @override
  Widget build(BuildContext context) {
    final titre = chauffeurs.length == 1
        ? '1 chauffeur proche'
        : '${chauffeurs.length} chauffeurs proches';
    return Container(
      decoration: const BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(TaamaRadius.xl)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              TaamaSpacing.lg, TaamaSpacing.sm, TaamaSpacing.lg, TaamaSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: TaamaColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: TaamaSpacing.md),
              Text(titre, style: TaamaText.title.copyWith(fontSize: 19)),
              const SizedBox(height: TaamaSpacing.xs),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: chauffeurs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: TaamaColors.border),
                  itemBuilder: (context, index) =>
                      _LigneChauffeur(chauffeur: chauffeurs[index]),
                ),
              ),
              const SizedBox(height: TaamaSpacing.sm),
              Text(
                'Pour choisir ton chauffeur, indique d’abord ta destination.',
                textAlign: TextAlign.center,
                style: TaamaText.body.copyWith(
                  fontSize: 12.5,
                  height: 1.4,
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

class _LigneChauffeur extends StatelessWidget {
  const _LigneChauffeur({required this.chauffeur});

  final ConducteurProche chauffeur;

  @override
  Widget build(BuildContext context) {
    final note = chauffeur.notePublique;
    final vehicule = (chauffeur.modeleVehicule ?? '').trim();
    // Note affichée seulement à partir de 5 notes (règle du radar) : jamais
    // le « 5.0 » offert d'office aux nouveaux.
    final vehiculeOuType = vehicule.isNotEmpty ? vehicule : (chauffeur.estMoto ? 'Moto' : 'Voiture');
    final style = TaamaText.body.copyWith(fontSize: 12.5, color: TaamaColors.textSecondary);
    final minutes = chauffeur.minutesAvant;
    return Semantics(
      label: '${chauffeur.prenom}, '
          '${note != null ? 'noté ${formaterNote(note)}' : 'nouveau chauffeur'}'
          '${minutes != null ? ', environ $minutes\u00a0min' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            AvatarChauffeur(
              graine: chauffeur.id,
              initiales: chauffeur.initiales,
              estMoto: chauffeur.estMoto,
              taille: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chauffeur.prenom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TaamaText.body.copyWith(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: [
                      if (note != null) ...[
                        // Icône, pas « ★ » : le caractère n'est pas dans la
                        // police embarquée.
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(Icons.star_rounded, size: 14, color: TaamaColors.star),
                        ),
                        TextSpan(text: ' ${formaterNote(note)}'),
                      ] else
                        const TextSpan(text: 'Nouveau'),
                      TextSpan(text: ' · $vehiculeOuType'),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ],
              ),
            ),
            if (minutes != null) ...[
              const SizedBox(width: 10),
              Text(
                'environ $minutes\u00a0min',
                style: TaamaText.body.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: TaamaColors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
