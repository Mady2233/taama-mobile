// lib/screens/mise_a_jour_requise_screen.dart
//
// Nouvelle version à installer (MiseAJour) : l'app s'arrête ici.
// Présentationnel : actions par callbacks (PageMiseAJourRequise). Aucun
// retour possible, deux boutons qui marchent toujours.

import 'package:flutter/material.dart';

import '../theme/taama_theme.dart';

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
    this.ios = false,
  });

  final VoidCallback onMettreAJour;

  /// Relance le démarrage (la mise à jour a pu s'installer entre-temps).
  final VoidCallback onReessayer;

  /// Google Play est en train de s'ouvrir : bouton occupé, jamais d'envoi
  /// en double.
  final bool enCours;

  /// Dernier essai sans succès : le dire, jamais un bouton muet.
  final AvisMiseAJour? avis;

  /// iPhone : la mise à jour passe par l'App Store, jamais par Google Play.
  final bool ios;

  List<(IconData, String)> get _atouts => [
    (Icons.verified_user_rounded, 'Ton compte et tes courses sont conservés'),
    (Icons.shield_rounded, ios ? 'Installation sécurisée par l’App Store' : 'Installation sécurisée par Google Play'),
    (Icons.auto_awesome_rounded, 'Les dernières améliorations de Taama'),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: TaamaColors.navy,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [TaamaColors.navyLight, TaamaColors.navy],
            ),
          ),
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        TaamaSpacing.xl, TaamaSpacing.xl, TaamaSpacing.xl, TaamaSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        const Center(child: _Embleme()),
                        const SizedBox(height: 28),
                        Text(
                          'Nouvelle version disponible',
                          textAlign: TextAlign.center,
                          style: TaamaText.title.copyWith(fontSize: 26, color: TaamaColors.textOnDark),
                        ),
                        const SizedBox(height: TaamaSpacing.md),
                        Text(
                          'Une version plus récente de Taama est prête. Installe-la pour continuer.',
                          textAlign: TextAlign.center,
                          style: TaamaText.body.copyWith(
                            fontSize: 15,
                            height: 1.45,
                            color: TaamaColors.onNavyMuted,
                          ),
                        ),
                        const SizedBox(height: TaamaSpacing.xl),
                        _Atouts(atouts: _atouts),
                        if (avis != null) ...[
                          const SizedBox(height: TaamaSpacing.md),
                          _Avis(avis: avis!, ios: ios),
                        ],
                        const Spacer(),
                        const SizedBox(height: TaamaSpacing.xl),
                        _BoutonMettreAJour(enCours: enCours, onPressed: onMettreAJour, ios: ios),
                        const SizedBox(height: TaamaSpacing.sm),
                        TextButton(
                          onPressed: enCours ? null : onReessayer,
                          style: TextButton.styleFrom(
                            foregroundColor: TaamaColors.onNavyMuted,
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
                  color: TaamaColors.textOnDark.withValues(alpha: 0.14 * (1 - t)),
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
              colors: [TaamaColors.routeNight, TaamaColors.primary],
            ),
            border: Border.all(color: TaamaColors.textOnDark.withValues(alpha: 0.25), width: 2),
            boxShadow: const [
              BoxShadow(color: TaamaColors.ombreMarqueur, blurRadius: 24, offset: Offset(0, 10)),
            ],
          ),
          child: const Icon(Icons.system_update_rounded, size: 46, color: TaamaColors.textOnDark),
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
      padding: const EdgeInsets.symmetric(horizontal: TaamaSpacing.lg, vertical: TaamaSpacing.sm),
      decoration: BoxDecoration(
        color: TaamaColors.textOnDark.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(TaamaRadius.xl),
        border: Border.all(color: TaamaColors.textOnDark.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          for (final (icone, texte) in atouts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: TaamaSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TaamaColors.accentMint.withValues(alpha: 0.16),
                    ),
                    child: Icon(icone, size: 17, color: TaamaColors.accentMint),
                  ),
                  const SizedBox(width: TaamaSpacing.md),
                  Expanded(
                    child: Text(
                      texte,
                      style: TaamaText.body.copyWith(fontSize: 14, color: TaamaColors.textOnDark),
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
  const _Avis({required this.avis, required this.ios});

  final AvisMiseAJour avis;
  final bool ios;

  @override
  Widget build(BuildContext context) {
    final texte = switch (avis) {
      AvisMiseAJour.annulee =>
        'Mise à jour annulée. Elle est nécessaire pour continuer à utiliser Taama.',
      AvisMiseAJour.playStoreIndisponible =>
        '${ios ? 'L’App Store' : 'Le Play Store'} ne s’est pas ouvert : ouvre-le toi-même et cherche « Taama ».',
    };
    return Container(
      padding: const EdgeInsets.all(TaamaSpacing.md),
      decoration: BoxDecoration(
        color: TaamaColors.warningSoft,
        borderRadius: BorderRadius.circular(TaamaRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_rounded, size: 20, color: TaamaColors.warning),
          const SizedBox(width: TaamaSpacing.sm),
          Expanded(
            child: Text(
              texte,
              style: TaamaText.body.copyWith(fontSize: 13.5, height: 1.35, color: TaamaColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoutonMettreAJour extends StatelessWidget {
  const _BoutonMettreAJour({required this.enCours, required this.onPressed, required this.ios});

  final bool enCours;
  final bool ios;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: enCours ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: TaamaColors.surface,
          foregroundColor: TaamaColors.navy,
          disabledBackgroundColor: TaamaColors.surface.withValues(alpha: 0.85),
          disabledForegroundColor: TaamaColors.navy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TaamaRadius.lg)),
          textStyle: TaamaText.body.copyWith(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (enCours)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: TaamaColors.navy),
              )
            else
              const Icon(Icons.download_rounded, size: 22),
            const SizedBox(width: TaamaSpacing.sm),
            // Petit écran ou grand texte : le libellé rétrécit, jamais coupé.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(enCours ? (ios ? 'Ouverture de l’App Store…' : 'Ouverture de Google Play…') : 'Mettre à jour'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
