// lib/widgets/bandeau_mise_a_jour.dart
//
// « Nouvelle version disponible » : bandeau qu'on peut fermer, au-dessus de
// tous les écrans (MaterialApp.builder), quand l'app est sous la version
// recommandée ou que Google Play en propose une plus récente. Fermé, il ne
// revient que pour une version plus récente (MiseAJour).

import 'package:flutter/material.dart';

import '../services/mise_a_jour.dart';
import '../theme/taama_theme.dart';

class BandeauMiseAJour extends StatelessWidget {
  const BandeauMiseAJour({
    super.key,
    required this.onMettreAJour,
    required this.onFermer,
    this.enCours = false,
    this.echec = false,
  });

  final VoidCallback onMettreAJour;
  final VoidCallback onFermer;
  final bool enCours;

  /// La fiche du store ne s'est pas ouverte : le dire, jamais un bouton muet.
  final bool echec;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.navy,
      elevation: 6,
      shadowColor: TaamaColors.ombreMarqueur,
      borderRadius: BorderRadius.circular(TaamaRadius.lg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(TaamaSpacing.md, TaamaSpacing.sm, TaamaSpacing.xs, TaamaSpacing.sm),
        child: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: TaamaColors.accentMint, size: 22),
            const SizedBox(width: TaamaSpacing.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nouvelle version disponible',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TaamaText.body.copyWith(fontSize: 14, color: TaamaColors.textOnDark),
                  ),
                  Text(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    echec ? 'Ouvre le Play Store et cherche « Taama ».' : 'Plus rapide et plus sûre.',
                    style: TaamaText.body.copyWith(fontSize: 12, color: TaamaColors.onNavyMuted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: enCours ? null : onMettreAJour,
              style: TextButton.styleFrom(
                foregroundColor: TaamaColors.accentMint,
                minimumSize: const Size(0, 44),
                textStyle: TaamaText.body.copyWith(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              // Petit écran ou grand texte : le libellé rétrécit.
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Mettre à jour')),
              ),
            ),
            // Pas de tooltip : posé au-dessus du Navigator (MaterialApp.builder),
            // le bandeau n'a pas d'Overlay, sans lequel un Tooltip ne se
            // construit pas. Le libellé passe par l'icône (lecteur d'écran).
            IconButton(
              onPressed: onFermer,
              icon: const Icon(Icons.close_rounded, color: TaamaColors.onNavyMuted, size: 20, semanticLabel: 'Fermer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// [child] avec le bandeau par-dessus, en haut, quand MiseAJour le demande.
class AvecBandeauMiseAJour extends StatefulWidget {
  const AvecBandeauMiseAJour({super.key, required this.child});

  final Widget child;

  @override
  State<AvecBandeauMiseAJour> createState() => _AvecBandeauMiseAJourState();
}

class _AvecBandeauMiseAJourState extends State<AvecBandeauMiseAJour> {
  bool _enCours = false;
  bool _echec = false;

  Future<void> _mettreAJour() async {
    setState(() {
      _enCours = true;
      _echec = false;
    });
    try {
      final issue = await MiseAJour.mettreAJour();
      if (!mounted) return;
      setState(() => _echec = issue == IssueMiseAJour.impossible);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MiseAJour.bandeauVisible,
      builder: (context, visible, enfant) => Stack(
        children: [
          enfant!,
          if (visible)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(TaamaSpacing.md),
                  child: BandeauMiseAJour(
                    onMettreAJour: _mettreAJour,
                    onFermer: MiseAJour.fermerBandeau,
                    enCours: _enCours,
                    echec: _echec,
                  ),
                ),
              ),
            ),
        ],
      ),
      child: widget.child,
    );
  }
}
