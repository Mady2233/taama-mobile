// lib/widgets/choix_offre.dart
//
// « Ton offre » : le client choisit son prix autour du prix standard, avant de
// commander. Limites du serveur (OffreLimites) ; l'app ne fait que se déplacer
// entre elles, le serveur revérifie l'offre à la commande.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/service_course.dart';
import '../theme/taama_theme.dart';
import '../utils/format.dart';

/// Ouvre la feuille ; l'offre choisie (avant promo), ou null si le client
/// ferme sans commander.
Future<int?> afficherChoixOffre(
  BuildContext context, {
  required String nomService,
  required OffreLimites limites,
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FeuilleOffre(
        nomService: nomService,
        limites: limites,
        onCommander: (prix) => Navigator.pop(context, prix),
      ),
    );

class FeuilleOffre extends StatefulWidget {
  const FeuilleOffre({
    super.key,
    required this.nomService,
    required this.limites,
    required this.onCommander,
  });

  final String nomService;
  final OffreLimites limites;
  final ValueChanged<int> onCommander;

  @override
  State<FeuilleOffre> createState() => _FeuilleOffreState();
}

class _FeuilleOffreState extends State<FeuilleOffre> {
  late int _prix = widget.limites.standard;

  void _choisir(int prix) {
    HapticFeedback.selectionClick();
    setState(() => _prix = prix);
  }

  @override
  Widget build(BuildContext context) {
    final limites = widget.limites;
    final ecart = _prix - limites.standard;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      decoration: const BoxDecoration(
        color: TaamaColors.night,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(TaamaSpacing.xl, TaamaSpacing.md, TaamaSpacing.xl, TaamaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: TaamaColors.nightBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: TaamaSpacing.lg),
              Row(
                children: [
                  Text('Ton offre', style: TaamaText.title.copyWith(fontSize: 20, color: TaamaColors.textOnDark)),
                  const SizedBox(width: TaamaSpacing.sm),
                  Flexible(
                    child: Text(
                      '· ${widget.nomService}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TaamaText.body.copyWith(fontSize: 15, color: TaamaColors.onNightMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TaamaSpacing.lg),

              // − prix +
              Container(
                padding: const EdgeInsets.all(TaamaSpacing.sm),
                decoration: BoxDecoration(
                  color: TaamaColors.nightRaised,
                  borderRadius: BorderRadius.circular(TaamaRadius.xl),
                ),
                child: Row(
                  children: [
                    _BoutonRond(
                      icone: Icons.remove_rounded,
                      infobulle: 'Baisser de ${formaterFcfa(limites.pas)}',
                      plein: false,
                      onPressed: limites.peutBaisser(_prix) ? () => _choisir(_prix - limites.pas) : null,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              formaterFcfa(_prix),
                              style: TaamaText.title.copyWith(fontSize: 36, color: TaamaColors.textOnDark, height: 1.1),
                            ),
                          ),
                          const SizedBox(height: TaamaSpacing.xs),
                          _Ecart(ecart: ecart),
                        ],
                      ),
                    ),
                    _BoutonRond(
                      icone: Icons.add_rounded,
                      infobulle: 'Monter de ${formaterFcfa(limites.pas)}',
                      plein: true,
                      onPressed: limites.peutMonter(_prix) ? () => _choisir(_prix + limites.pas) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TaamaSpacing.md),

              // Montants d'un toucher
              Wrap(
                spacing: TaamaSpacing.sm,
                runSpacing: TaamaSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  for (final prix in limites.raccourcis)
                    ChoiceChip(
                      label: Text(prix == limites.standard ? 'Standard' : formaterFcfa(prix)),
                      selected: prix == _prix,
                      onSelected: (_) => _choisir(prix),
                      showCheckmark: false,
                      backgroundColor: TaamaColors.nightControl,
                      selectedColor: TaamaColors.primary,
                      side: BorderSide.none,
                      labelStyle: TaamaText.body.copyWith(fontSize: 13, color: TaamaColors.textOnDark),
                    ),
                ],
              ),
              const SizedBox(height: TaamaSpacing.md),
              Text(
                ecart < 0
                    ? 'Offre plus basse que le standard : un chauffeur peut l’accepter, la refuser ou te proposer un autre prix. Tu as toujours le dernier mot.'
                    : 'Le chauffeur accepte ce prix, ou te propose un autre prix. Tu as toujours le dernier mot.',
                textAlign: TextAlign.center,
                style: TaamaText.body.copyWith(fontSize: 12.5, height: 1.4, color: TaamaColors.onNightMuted),
              ),
              const SizedBox(height: TaamaSpacing.lg),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: () => widget.onCommander(_prix),
                  style: FilledButton.styleFrom(
                    backgroundColor: TaamaColors.accentMint,
                    foregroundColor: TaamaColors.onAccentMint,
                    textStyle: TaamaText.body.copyWith(fontSize: 16.5, fontWeight: FontWeight.w800),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Commander · ${formaterFcfa(_prix)}'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// « Standard », ou l'écart au standard dans une pastille.
class _Ecart extends StatelessWidget {
  const _Ecart({required this.ecart});

  final int ecart;

  @override
  Widget build(BuildContext context) {
    if (ecart == 0) {
      return Text('Prix standard', style: TaamaText.muted.copyWith(fontSize: 13, color: TaamaColors.onNightMuted));
    }
    final couleur = ecart < 0 ? TaamaColors.accentMint : TaamaColors.routeNight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(TaamaRadius.pill),
      ),
      child: Text(
        '${ecart > 0 ? '+' : '−'}${formaterFcfa(ecart.abs())} sur le standard',
        style: TaamaText.body.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: couleur),
      ),
    );
  }
}

class _BoutonRond extends StatelessWidget {
  const _BoutonRond({required this.icone, required this.infobulle, required this.plein, required this.onPressed});

  final IconData icone;
  final String infobulle;
  final bool plein;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final actif = onPressed != null;
    return Tooltip(
      message: infobulle,
      child: Material(
        shape: const CircleBorder(),
        color: !actif ? TaamaColors.nightControl : (plein ? TaamaColors.primary : TaamaColors.nightControl),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              icone,
              size: 26,
              color: actif ? TaamaColors.textOnDark : TaamaColors.onNightFaint,
            ),
          ),
        ),
      ),
    );
  }
}
