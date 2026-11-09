// lib/widgets/carte_contre_offre.dart
//
// Prix proposé par le chauffeur, en attente de la réponse du client.
// Présentationnel : données par paramètres, actions par callbacks
// (suivi_course_page.dart). Aucune identité du chauffeur ici : il n'a pas
// encore accepté la course.

import 'package:flutter/material.dart';

import '../theme/taama_theme.dart';
import '../utils/format.dart';

/// Bloc `contre_offre` d'une demande, tel qu'envoyé par le serveur. Montants
/// que paierait le client, promo comprise.
class ContreOffreClient {
  const ContreOffreClient({
    required this.prixPropose,
    required this.prixActuel,
    required this.secondesRestantes,
    this.minutesApproche,
    this.note,
    this.categorie,
  });

  final int prixPropose;
  final int prixActuel;
  final int secondesRestantes;
  final int? minutesApproche;
  final double? note;
  final String? categorie;

  /// Null si le bloc est absent ou incomplet : rien n'est affiché, jamais un
  /// prix inventé.
  static ContreOffreClient? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final propose = (brut['prix_propose'] as num?)?.toInt();
    final actuel = (brut['prix_actuel'] as num?)?.toInt();
    final secondes = (brut['secondes_restantes'] as num?)?.toInt();
    if (propose == null || actuel == null || secondes == null) return null;
    final categorie = brut['categorie']?.toString().trim();
    return ContreOffreClient(
      prixPropose: propose,
      prixActuel: actuel,
      secondesRestantes: secondes,
      minutesApproche: (brut['minutes_approche'] as num?)?.toInt(),
      note: double.tryParse(brut['note']?.toString() ?? ''),
      categorie: (categorie == null || categorie.isEmpty) ? null : categorie,
    );
  }
}

/// Durée affichée au client pour répondre (le serveur garde une marge).
const int dureeReponseContreOffreSecondes = 30;

class CarteContreOffre extends StatelessWidget {
  const CarteContreOffre({
    super.key,
    required this.offre,
    required this.secondesRestantes,
    required this.onAccepter,
    required this.onRefuser,
    this.reponseEnCours,
  });

  final ContreOffreClient offre;

  /// Décompté chaque seconde par la page, recalé à chaque rafraîchissement.
  final int secondesRestantes;

  /// `true` pendant l'envoi d'« Accepter », `false` pendant celui de
  /// « Refuser », null sinon.
  final bool? reponseEnCours;
  final VoidCallback onAccepter;
  final VoidCallback onRefuser;

  @override
  Widget build(BuildContext context) {
    final expiree = secondesRestantes <= 0;
    final envoi = reponseEnCours != null;
    final details = [
      if (offre.minutesApproche != null) 'À ${offre.minutesApproche} min de toi',
      if (offre.categorie != null) offre.categorie!,
      if (offre.note != null && offre.note! > 0) '★ ${formaterNote(offre.note!)}',
    ];

    return Material(
      color: TaamaColors.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(TaamaRadius.xl),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(TaamaRadius.xl),
          boxShadow: TaamaShadows.floating,
        ),
        padding: const EdgeInsets.all(TaamaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouveau prix proposé', style: TaamaText.muted.copyWith(fontSize: 13)),
            const SizedBox(height: TaamaSpacing.sm),
            Text(
              'Le chauffeur propose ${formaterFcfa(offre.prixPropose)} au lieu de ${formaterFcfa(offre.prixActuel)}',
              style: TaamaText.title.copyWith(fontSize: 21, height: 1.25),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: TaamaSpacing.sm),
              Text(details.join(' · '), style: TaamaText.muted),
            ],
            const SizedBox(height: TaamaSpacing.lg),
            if (expiree)
              Text(
                'Délai dépassé : nous cherchons un autre chauffeur au prix de ${formaterFcfa(offre.prixActuel)}.',
                style: TaamaText.body,
              )
            else ...[
              Text('$secondesRestantes s pour répondre', style: TaamaText.muted.copyWith(fontSize: 13)),
              const SizedBox(height: TaamaSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(TaamaRadius.pill),
                child: LinearProgressIndicator(
                  value: (secondesRestantes / dureeReponseContreOffreSecondes).clamp(0.0, 1.0),
                  minHeight: 6,
                  color: TaamaColors.primary,
                  backgroundColor: TaamaColors.primarySoft,
                ),
              ),
              const SizedBox(height: TaamaSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: envoi ? null : onRefuser,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                      child: reponseEnCours == false ? const _Envoi() : const Text('Refuser'),
                    ),
                  ),
                  const SizedBox(width: TaamaSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: envoi ? null : onAccepter,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                      child: reponseEnCours == true ? const _Envoi(clair: true) : const Text('Accepter'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TaamaSpacing.sm),
              Text(
                'Si tu refuses, la course est proposée à un autre chauffeur au prix de ${formaterFcfa(offre.prixActuel)}.',
                style: TaamaText.muted.copyWith(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Envoi extends StatelessWidget {
  const _Envoi({this.clair = false});

  final bool clair;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: clair ? TaamaColors.textOnDark : TaamaColors.primary,
        ),
      );
}
