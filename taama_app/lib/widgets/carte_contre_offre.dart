// lib/widgets/carte_contre_offre.dart
//
// Contre-proposition du chauffeur, en attente de la réponse du client.
// Présentationnel : données par paramètres, actions par callbacks
// (suivi_course_page.dart). Aucune identité du chauffeur ici : il n'a pas
// encore accepté la course.

import 'package:flutter/material.dart';

import '../theme/taama_theme.dart';
import '../utils/format.dart';

/// Bloc `contre_offre` d'une demande, tel qu'envoyé par le serveur, plus le
/// contexte de la demande. Montants que paierait le client, promo comprise.
class ContreOffreClient {
  const ContreOffreClient({
    required this.prixPropose,
    required this.prixActuel,
    required this.secondesRestantes,
    this.minutesApproche,
    this.note,
    this.categorie,
    this.aOffre = false,
    this.prixStandard,
    this.distanceKm,
  });

  final int prixPropose;

  /// Ce que le client paie aujourd'hui : son offre, sinon le prix standard.
  final int prixActuel;
  final int secondesRestantes;
  final int? minutesApproche;
  final double? note;
  final String? categorie;

  /// Le client a fait une offre à la commande.
  final bool aOffre;

  /// Prix standard du devis : seulement sans promo (sinon il ne se compare
  /// pas aux montants affichés, qui la déduisent).
  final int? prixStandard;
  final double? distanceKm;

  /// Null si le bloc est absent ou incomplet : rien n'est affiché, jamais un
  /// prix inventé. [demande] : la demande entière, pour son contexte.
  static ContreOffreClient? depuisJson(Object? brut, {Map<String, dynamic>? demande}) {
    if (brut is! Map) return null;
    final propose = (brut['prix_propose'] as num?)?.toInt();
    final actuel = (brut['prix_actuel'] as num?)?.toInt();
    final secondes = (brut['secondes_restantes'] as num?)?.toInt();
    if (propose == null || actuel == null || secondes == null) return null;
    final categorie = brut['categorie']?.toString().trim();
    final offert = (demande?['prix_offert'] as num?)?.toInt();
    final standard = (demande?['prix_standard'] as num?)?.toInt();
    final reference = offert ?? standard;
    return ContreOffreClient(
      prixPropose: propose,
      prixActuel: actuel,
      secondesRestantes: secondes,
      minutesApproche: (brut['minutes_approche'] as num?)?.toInt(),
      note: double.tryParse(brut['note']?.toString() ?? ''),
      categorie: (categorie == null || categorie.isEmpty) ? null : categorie,
      aOffre: offert != null,
      prixStandard: reference != null && reference == actuel ? standard : null,
      distanceKm: double.tryParse(demande?['distance_km']?.toString() ?? ''),
    );
  }
}

/// Durée affichée au client pour répondre (le serveur garde une marge).
const int dureeReponseContreOffreSecondes = 45;

class CarteContreOffre extends StatelessWidget {
  const CarteContreOffre({
    super.key,
    required this.offre,
    required this.secondesRestantes,
    required this.onAccepter,
    required this.onRefuser,
    this.reponseEnCours,
    this.paiement,
  });

  final ContreOffreClient offre;

  /// Décompté chaque seconde par la page, recalé à chaque rafraîchissement.
  final int secondesRestantes;

  /// `true` pendant l'envoi d'« Accepter », `false` pendant celui de
  /// « Refuser », null sinon.
  final bool? reponseEnCours;
  final VoidCallback onAccepter;
  final VoidCallback onRefuser;

  /// « Espèces » ou « Portefeuille » ; masqué si null.
  final String? paiement;

  @override
  Widget build(BuildContext context) {
    final expiree = secondesRestantes <= 0;
    final envoi = reponseEnCours != null;
    final ecart = offre.prixPropose - offre.prixActuel;
    final details = [
      if (offre.note != null && offre.note! > 0) '★ ${formaterNote(offre.note!)}',
      if (offre.minutesApproche != null) 'à ${offre.minutesApproche} min de toi',
      if (offre.categorie != null) offre.categorie!,
    ];
    final libelleActuel = offre.aOffre ? 'Ton offre' : 'Prix actuel';
    final garder = offre.aOffre ? 'garder mon offre' : 'garder le prix';
    final stats = [
      if (offre.distanceKm != null) ('Trajet', '${offre.distanceKm!.toStringAsFixed(1).replaceAll('.', ',')} km'),
      if (offre.prixStandard != null) ('Standard', formaterFcfa(offre.prixStandard!)),
      if (paiement != null) ('Paiement', paiement!),
    ];

    return Container(
      decoration: BoxDecoration(
        color: TaamaColors.night,
        borderRadius: BorderRadius.circular(TaamaRadius.xl),
        boxShadow: TaamaShadows.floating,
      ),
      padding: const EdgeInsets.all(TaamaSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Un chauffeur te répond',
                      style: TaamaText.title.copyWith(fontSize: 18, color: TaamaColors.textOnDark),
                    ),
                    if (details.isNotEmpty)
                      Text(details.join(' · '), style: TaamaText.body.copyWith(fontSize: 13, color: TaamaColors.onNightMuted)),
                  ],
                ),
              ),
              if (!expiree) _Decompte(secondes: secondesRestantes),
            ],
          ),
          const SizedBox(height: TaamaSpacing.lg),
          Text(
            'Il te contre-propose',
            textAlign: TextAlign.center,
            style: TaamaText.body.copyWith(fontSize: 14, color: TaamaColors.onNightMuted),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formaterFcfa(offre.prixPropose),
              style: TaamaText.title.copyWith(fontSize: 40, color: TaamaColors.textOnDark, height: 1.15),
            ),
          ),
          const SizedBox(height: TaamaSpacing.xs),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: TaamaSpacing.sm,
            children: [
              Text(
                '$libelleActuel ${formaterFcfa(offre.prixActuel)}',
                style: TaamaText.body.copyWith(fontSize: 14, color: TaamaColors.onNightMuted),
              ),
              if (ecart != 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                  decoration: BoxDecoration(
                    color: (ecart > 0 ? TaamaColors.dangerNight : TaamaColors.accentMint).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(TaamaRadius.pill),
                  ),
                  child: Text(
                    '${ecart > 0 ? '+' : '−'}${formaterFcfa(ecart.abs())}',
                    style: TaamaText.body.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: ecart > 0 ? TaamaColors.dangerNight : TaamaColors.accentMint,
                    ),
                  ),
                ),
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: TaamaSpacing.lg),
            Row(
              children: [
                for (final (titre, valeur) in stats)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: TaamaSpacing.xs),
                      padding: const EdgeInsets.symmetric(vertical: TaamaSpacing.sm),
                      decoration: BoxDecoration(
                        color: TaamaColors.nightRaised,
                        borderRadius: BorderRadius.circular(TaamaRadius.md),
                      ),
                      child: Column(
                        children: [
                          Text(titre, style: TaamaText.body.copyWith(fontSize: 11.5, color: TaamaColors.onNightFaint)),
                          const SizedBox(height: 2),
                          Text(valeur, style: TaamaText.body.copyWith(fontSize: 13.5, color: TaamaColors.textOnDark)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: TaamaSpacing.lg),
          if (expiree)
            Text(
              'Délai dépassé : nous cherchons un autre chauffeur au prix de ${formaterFcfa(offre.prixActuel)}.',
              textAlign: TextAlign.center,
              style: TaamaText.body.copyWith(color: TaamaColors.textOnDark),
            )
          else ...[
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: envoi ? null : onAccepter,
                style: FilledButton.styleFrom(
                  backgroundColor: TaamaColors.accentMint,
                  foregroundColor: TaamaColors.onAccentMint,
                  textStyle: TaamaText.body.copyWith(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                child: reponseEnCours == true
                    ? const _Envoi()
                    : FittedBox(fit: BoxFit.scaleDown, child: Text('Accepter ${formaterFcfa(offre.prixPropose)}')),
              ),
            ),
            const SizedBox(height: TaamaSpacing.xs),
            TextButton(
              onPressed: envoi ? null : onRefuser,
              style: TextButton.styleFrom(
                foregroundColor: TaamaColors.onNightMuted,
                minimumSize: const Size(0, 48),
                textStyle: TaamaText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              child: reponseEnCours == false
                  ? const _Envoi()
                  : Text('Refuser : $garder à ${formaterFcfa(offre.prixActuel)}', textAlign: TextAlign.center),
            ),
            Text(
              'Si tu refuses, la course est proposée à un autre chauffeur à ${formaterFcfa(offre.prixActuel)}.',
              textAlign: TextAlign.center,
              style: TaamaText.body.copyWith(fontSize: 12, color: TaamaColors.onNightFaint),
            ),
          ],
        ],
      ),
    );
  }
}

/// Anneau des secondes restantes.
class _Decompte extends StatelessWidget {
  const _Decompte({required this.secondes});

  final int secondes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: (secondes / dureeReponseContreOffreSecondes).clamp(0.0, 1.0),
              strokeWidth: 4,
              color: secondes <= 10 ? TaamaColors.dangerNight : TaamaColors.accentMint,
              backgroundColor: TaamaColors.nightControl,
            ),
          ),
          Text('$secondes s', style: TaamaText.body.copyWith(fontSize: 13, color: TaamaColors.textOnDark)),
        ],
      ),
    );
  }
}

class _Envoi extends StatelessWidget {
  const _Envoi();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: TaamaColors.textOnDark),
      );
}
