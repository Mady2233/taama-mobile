import 'package:flutter/material.dart';
import '../theme/taama_theme.dart';

/// Après une déconnexion qui n'a pas joint le serveur (Deconnexion).
const String messageDeconnexionHorsReseau =
    'Ce téléphone est déconnecté. Sans réseau, tu restes connecté sur tes autres téléphones.';

/// Confirmation avant la déconnexion : le serveur ferme la session sur tous
/// les appareils du compte (jeton partagé). Vrai si l'utilisateur confirme.
Future<bool> demanderConfirmationDeconnexion(BuildContext context) async {
  final confirme = await showDialog<bool>(
    context: context,
    builder: (dialogue) => AlertDialog(
      title: const Text('Se déconnecter ?'),
      content: const Text('Tu seras déconnecté de Taama sur tous tes appareils.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogue, false),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogue, true),
          style: TextButton.styleFrom(foregroundColor: TaamaColors.danger),
          child: const Text('Se déconnecter'),
        ),
      ],
    ),
  );
  return confirme ?? false;
}
