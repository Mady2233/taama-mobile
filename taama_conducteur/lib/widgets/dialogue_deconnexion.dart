import 'package:flutter/material.dart';

/// Après une déconnexion qui n'a pas joint le serveur (Deconnexion).
const String messageDeconnexionHorsReseau =
    'Ce téléphone est déconnecté. Sans réseau, tu restes connecté sur tes autres téléphones.';

/// Confirmation avant la déconnexion : le serveur ferme la session sur tous
/// les appareils du compte (jeton partagé). Vrai si le chauffeur confirme.
Future<bool> demanderConfirmationDeconnexion(BuildContext context) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (dialogue) => AlertDialog(
      title: const Text('Se déconnecter ?'),
      content: const Text(
        'Tu ne recevras plus de courses sur ce téléphone. '
        'Tu seras aussi déconnecté de Taama sur tes autres appareils.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogue, false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogue, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Se déconnecter'),
        ),
      ],
    ),
  );
  return confirme ?? false;
}

/// Ses courses n'ont pas pu être vérifiées (réseau) : rester connecté, ou se
/// déconnecter quand même. Vrai s'il se déconnecte quand même.
Future<bool> demanderDeconnexionQuandMeme(BuildContext context) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (dialogue) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Impossible de vérifier tes courses. Vérifie ton réseau et réessaie.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Si tu as une course en cours, tu ne pourras plus la suivre.',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogue, false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogue, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Se déconnecter quand même'),
        ),
      ],
    ),
  );
  return confirme ?? false;
}
