// « Vérifier mon identité » — écran PUREMENT présentationnel : données par
// paramètres, actions par callbacks (logique dans verification_identite_page.dart).
// Facultatif, et dit comme tel : la commande d'une course n'en dépend jamais.

import 'package:flutter/material.dart';

import '../models/verification_identite.dart';
import '../theme/taama_theme.dart';

class EcranVerificationIdentite extends StatelessWidget {
  const EcranVerificationIdentite({
    super.key,
    required this.chargement,
    required this.erreur,
    required this.verification,
    required this.envoiEnCours,
    required this.onReessayer,
    required this.onPrendrePhoto,
    required this.onChoisirPhoto,
  });

  final bool chargement;
  final String? erreur;
  final VerificationIdentite? verification;
  final bool envoiEnCours;
  final VoidCallback onReessayer;
  final VoidCallback onPrendrePhoto;
  final VoidCallback onChoisirPhoto;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TaamaColors.background,
      appBar: AppBar(
        title: const Text('Vérifier mon identité'),
        backgroundColor: TaamaColors.background,
        foregroundColor: TaamaColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(child: _corps()),
    );
  }

  Widget _corps() {
    if (chargement) return const Center(child: CircularProgressIndicator());
    final v = verification;
    if (erreur != null || v == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 40, color: TaamaColors.textSecondary),
              const SizedBox(height: 12),
              Text(
                erreur ?? 'Impossible de lire ta vérification.',
                textAlign: TextAlign.center,
                style: TaamaText.body,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onReessayer, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CarteStatut(verification: v),
          const SizedBox(height: 16),
          const _Explications(),
          if (v.peutEnvoyer) ...[
            const SizedBox(height: 20),
            Text(
              v.statut == StatutIdentite.nonSoumis ? 'Envoyer ma pièce' : 'Envoyer une autre photo',
              style: TaamaText.title.copyWith(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'Carte d’identité ou passeport, entier, bien éclairé, lisible.',
              style: TaamaText.muted.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: envoiEnCours ? null : onPrendrePhoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Prendre une photo'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: envoiEnCours ? null : onChoisirPhoto,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choisir dans la galerie'),
            ),
            if (envoiEnCours) ...[
              const SizedBox(height: 14),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Envoi en cours…'),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CarteStatut extends StatelessWidget {
  const _CarteStatut({required this.verification});

  final VerificationIdentite verification;

  @override
  Widget build(BuildContext context) {
    final (icone, couleur, fond, titre, texte) = switch (verification.statut) {
      StatutIdentite.nonSoumis => (
          Icons.badge_outlined,
          TaamaColors.primary,
          TaamaColors.primarySoft,
          'Identité non vérifiée',
          'Tu peux faire vérifier ta pièce d’identité. C’est facultatif.',
        ),
      StatutIdentite.enAttente => (
          Icons.hourglass_top_rounded,
          TaamaColors.warning,
          TaamaColors.warningSoft,
          'Vérification en cours',
          'Ta pièce est bien reçue. Nous te prévenons dès qu’elle est vérifiée.',
        ),
      StatutIdentite.approuve => (
          Icons.verified_user_rounded,
          TaamaColors.success,
          TaamaColors.successSoft,
          'Identité vérifiée',
          'Les chauffeurs voient « Client vérifié » quand tu commandes.',
        ),
      StatutIdentite.refuse => (
          Icons.error_outline_rounded,
          TaamaColors.danger,
          TaamaColors.dangerSoft,
          'Pièce refusée',
          'Ta pièce n’a pas pu être vérifiée. Tu peux envoyer une autre photo.',
        ),
    };
    final motif = verification.motifRefus;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: couleur, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: TaamaText.title.copyWith(fontSize: 16, color: couleur)),
                const SizedBox(height: 4),
                Text(texte, style: TaamaText.body.copyWith(fontSize: 14)),
                if (motif != null) ...[
                  const SizedBox(height: 8),
                  Text('Motif : $motif',
                      style: TaamaText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Explications extends StatelessWidget {
  const _Explications();

  @override
  Widget build(BuildContext context) {
    Widget ligne(IconData icone, String texte) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, size: 20, color: TaamaColors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(texte, style: TaamaText.body.copyWith(fontSize: 14))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        boxShadow: TaamaShadows.card,
      ),
      child: Column(
        children: [
          ligne(Icons.two_wheeler_rounded,
              'Facultatif : tu commandes tes courses de la même façon, avec ou sans.'),
          ligne(Icons.verified_user_outlined,
              'Les chauffeurs voient seulement « Client vérifié », jamais ta pièce.'),
          ligne(Icons.lock_outline_rounded,
              'Ta pièce reste privée : seule l’équipe Taama qui vérifie peut la voir.'),
        ],
      ),
    );
  }
}
