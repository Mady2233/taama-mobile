// lib/screens/mise_a_jour_requise_screen.dart
//
// Version trop ancienne (MiseAJour) : l'app s'arrête ici. Présentationnel :
// actions par callbacks (écran de démarrage). Aucun retour possible, deux
// boutons qui marchent toujours.

import 'package:flutter/material.dart';

import '../theme/couleurs_taama.dart';

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
        backgroundColor: CouleursTaama.sable,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.system_update_rounded, size: 64, color: CouleursTaama.terreCuite),
                  const SizedBox(height: 18),
                  const Text(
                    'Nouvelle version disponible',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: CouleursTaama.indigo),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pour continuer à recevoir des courses, installe la mise à jour depuis le Play Store.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.4, color: CouleursTaama.grisTexte),
                  ),
                  if (playStoreIndisponible) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Le Play Store ne s’est pas ouvert : ouvre-le toi-même et cherche « Taama Conducteur ».',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CouleursTaama.terreCuite),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: onMettreAJour,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CouleursTaama.terreCuite,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Mettre à jour', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onReessayer,
                    style: TextButton.styleFrom(
                      foregroundColor: CouleursTaama.indigo,
                      minimumSize: const Size(0, 48),
                    ),
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
