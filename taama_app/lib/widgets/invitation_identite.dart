// Bandeau discret de l'accueil : invite à faire vérifier son identité. Placé
// sous la recherche et les services, jamais devant : la commande n'en dépend
// pas. Toujours fermable (voir home_page.dart pour la mémoire de ce choix).

import 'package:flutter/material.dart';

import '../theme/taama_theme.dart';

enum InvitationIdentite { aVerifier, aRenvoyer }

class BandeauInvitationIdentite extends StatelessWidget {
  const BandeauInvitationIdentite({
    super.key,
    required this.invitation,
    required this.onOuvrir,
    required this.onMasquer,
  });

  final InvitationIdentite invitation;
  final VoidCallback onOuvrir;
  final VoidCallback onMasquer;

  @override
  Widget build(BuildContext context) {
    final (titre, texte) = switch (invitation) {
      InvitationIdentite.aVerifier => (
          'Fais vérifier ton identité',
          'Facultatif : les chauffeurs verront « Client vérifié ».',
        ),
      InvitationIdentite.aRenvoyer => (
          'Ta pièce n’a pas pu être vérifiée',
          'Envoie une autre photo, quand tu veux.',
        ),
    };
    return Material(
      color: TaamaColors.primarySoft,
      borderRadius: BorderRadius.circular(TaamaRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        onTap: onOuvrir,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: TaamaColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre,
                        style: TaamaText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(texte, style: TaamaText.muted.copyWith(fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Masquer',
                onPressed: onMasquer,
                icon: const Icon(Icons.close_rounded, color: TaamaColors.textSecondary, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
