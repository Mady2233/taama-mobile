// lib/screens/mise_a_jour_requise_screen.dart
//
// Nouvelle version à installer (MiseAJour) : l'app s'arrête ici.
// Présentationnel : actions par callbacks (PageMiseAJourRequise). Aucun
// retour possible, deux boutons qui marchent toujours.

import 'package:flutter/material.dart';

import '../theme/couleurs_taama.dart';

/// Message affiché après un essai qui n'a pas abouti.
enum AvisMiseAJour {
  /// L'utilisateur a fermé l'écran de Google Play.
  annulee,

  /// Ni la mise à jour de Google Play ni la fiche du Play Store n'ont pu
  /// s'ouvrir.
  playStoreIndisponible,
}

class EcranMiseAJourRequise extends StatelessWidget {
  const EcranMiseAJourRequise({
    super.key,
    required this.onMettreAJour,
    required this.onReessayer,
    this.enCours = false,
    this.avis,
  });

  final VoidCallback onMettreAJour;

  /// Relance le démarrage (la mise à jour a pu s'installer entre-temps).
  final VoidCallback onReessayer;

  /// Google Play est en train de s'ouvrir : bouton occupé, jamais d'envoi
  /// en double.
  final bool enCours;

  /// Dernier essai sans succès : le dire, jamais un bouton muet.
  final AvisMiseAJour? avis;

  static const List<(IconData, String)> _atouts = [
    (Icons.verified_user_rounded, 'Ton compte, tes gains et tes courses sont conservés'),
    (Icons.shield_rounded, 'Installation sécurisée par Google Play'),
    (Icons.auto_awesome_rounded, 'Les dernières améliorations de Taama Conducteur'),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: CouleursTaama.indigo,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [CouleursTaama.indigo, CouleursTaama.nuitPanneau],
            ),
          ),
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        const Center(child: _Embleme()),
                        const SizedBox(height: 28),
                        const Text(
                          'Nouvelle version disponible',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            color: CouleursTaama.blanc,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Une version plus récente de Taama Conducteur est prête. '
                          'Installe-la pour continuer à recevoir des courses.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, height: 1.45, color: CouleursTaama.nuitTexteSecondaire),
                        ),
                        const SizedBox(height: 24),
                        const _Atouts(atouts: _atouts),
                        if (avis != null) ...[
                          const SizedBox(height: 12),
                          _Avis(avis: avis!),
                        ],
                        const Spacer(),
                        const SizedBox(height: 24),
                        _BoutonMettreAJour(enCours: enCours, onPressed: onMettreAJour),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: enCours ? null : onReessayer,
                          style: TextButton.styleFrom(
                            foregroundColor: CouleursTaama.nuitTexteSecondaire,
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastille de l'icône, avec un halo qui respire (immobile si les
/// animations sont réduites).
class _Embleme extends StatefulWidget {
  const _Embleme();

  @override
  State<_Embleme> createState() => _EmblemeState();
}

class _EmblemeState extends State<_Embleme> with SingleTickerProviderStateMixin {
  late final AnimationController _halo =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _halo.stop();
      _halo.value = 0.5;
    } else if (!_halo.isAnimating) {
      _halo.repeat();
    }
  }

  @override
  void dispose() {
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 150,
      child: AnimatedBuilder(
        animation: _halo,
        builder: (context, child) {
          final t = Curves.easeOut.transform(_halo.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 104 + 46 * t,
                height: 104 + 46 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CouleursTaama.terreCuite.withValues(alpha: 0.30 * (1 - t)),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [CouleursTaama.or, CouleursTaama.terreCuite],
            ),
            border: Border.all(color: CouleursTaama.blanc.withValues(alpha: 0.25), width: 2),
            boxShadow: const [
              BoxShadow(color: CouleursTaama.ombre, blurRadius: 24, offset: Offset(0, 10)),
            ],
          ),
          child: const Icon(Icons.system_update_rounded, size: 46, color: CouleursTaama.blanc),
        ),
      ),
    );
  }
}

class _Atouts extends StatelessWidget {
  const _Atouts({required this.atouts});

  final List<(IconData, String)> atouts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: CouleursTaama.blanc.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CouleursTaama.blanc.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          for (final (icone, texte) in atouts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CouleursTaama.or.withValues(alpha: 0.18),
                    ),
                    child: Icon(icone, size: 17, color: CouleursTaama.or),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      texte,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CouleursTaama.blanc,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Avis extends StatelessWidget {
  const _Avis({required this.avis});

  final AvisMiseAJour avis;

  @override
  Widget build(BuildContext context) {
    final texte = switch (avis) {
      AvisMiseAJour.annulee =>
        'Mise à jour annulée. Elle est nécessaire pour continuer à recevoir des courses.',
      AvisMiseAJour.playStoreIndisponible =>
        'Le Play Store ne s’est pas ouvert : ouvre-le toi-même et cherche « Taama Conducteur ».',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CouleursTaama.sable,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_rounded, size: 20, color: CouleursTaama.terreCuite),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: CouleursTaama.indigo,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoutonMettreAJour extends StatelessWidget {
  const _BoutonMettreAJour({required this.enCours, required this.onPressed});

  final bool enCours;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: enCours ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: CouleursTaama.terreCuite,
          foregroundColor: CouleursTaama.blanc,
          disabledBackgroundColor: CouleursTaama.terreCuite.withValues(alpha: 0.75),
          disabledForegroundColor: CouleursTaama.blanc,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (enCours)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: CouleursTaama.blanc),
              )
            else
              const Icon(Icons.download_rounded, size: 22),
            const SizedBox(width: 8),
            // Petit écran ou grand texte : le libellé rétrécit, jamais coupé.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(enCours ? 'Ouverture de Google Play…' : 'Mettre à jour'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
