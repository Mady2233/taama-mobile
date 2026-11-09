// lib/screens/mise_a_jour_requise_screen.dart
//
// Version trop ancienne (MiseAJour) : l'app s'arrête ici. Présentationnel :
// actions par callbacks (écran de démarrage). Aucun retour possible, deux
// boutons qui marchent toujours.

import 'package:flutter/material.dart';

import '../theme/taama_theme.dart';

class EcranMiseAJourRequise extends StatelessWidget {
  const EcranMiseAJourRequise({
    super.key,
    required this.onMettreAJour,
    required this.onReessayer,
    this.playStoreIndisponible = false,
  });

  final VoidCallback onMettreAJour;

  /// Relance le démarrage (la version minimale a pu baisser).
  final VoidCallback onReessayer;

  /// Le Play Store n'a pas pu s'ouvrir : le dire, jamais un bouton muet.
  final bool playStoreIndisponible;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: TaamaColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(TaamaSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.system_update_rounded, size: 64, color: TaamaColors.primary),
                  const SizedBox(height: TaamaSpacing.lg),
                  Text(
                    'Nouvelle version disponible',
                    textAlign: TextAlign.center,
                    style: TaamaText.title.copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: TaamaSpacing.md),
                  Text(
                    'Pour continuer à utiliser Taama, installe la mise à jour depuis le Play Store.',
                    textAlign: TextAlign.center,
                    style: TaamaText.muted.copyWith(fontSize: 15, height: 1.4),
                  ),
                  if (playStoreIndisponible) ...[
                    const SizedBox(height: TaamaSpacing.md),
                    Text(
                      'Le Play Store ne s’est pas ouvert : ouvre-le toi-même et cherche « Taama ».',
                      textAlign: TextAlign.center,
                      style: TaamaText.body.copyWith(color: TaamaColors.warning),
                    ),
                  ],
                  const SizedBox(height: TaamaSpacing.xl),
                  FilledButton.icon(
                    onPressed: onMettreAJour,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Mettre à jour'),
                  ),
                  const SizedBox(height: TaamaSpacing.sm),
                  TextButton(
                    onPressed: onReessayer,
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
