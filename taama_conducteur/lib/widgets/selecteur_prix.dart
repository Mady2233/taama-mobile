// lib/widgets/selecteur_prix.dart
//
// Prix ajustable de la demande entrante : le prix au centre, − et + de chaque
// côté. Présentationnel : montants et actions par paramètres (calculés par
// PrixAjustable dans l'écran). Un bouton à sa limite, ou pendant un envoi,
// est grisé : le serveur ne l'accepterait pas.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../theme/couleurs_taama.dart';
import '../utils/format.dart';

class SelecteurPrix extends StatelessWidget {
  const SelecteurPrix({
    super.key,
    required this.prix,
    required this.ecart,
    required this.pas,
    required this.surBaisser,
    required this.surMonter,
  });

  /// Montant affiché au centre : ce que le chauffeur encaissera.
  final int prix;

  /// Écart au prix standard (négatif : plus bas).
  final int ecart;

  /// Montant d'un appui.
  final int pas;

  /// Null : bouton grisé.
  final VoidCallback? surBaisser;
  final VoidCallback? surMonter;

  static const TextStyle _stylePrix = TextStyle(
    color: CouleursTaama.terreCuite,
    fontWeight: FontWeight.w900,
    fontSize: 34,
    height: 1,
    letterSpacing: -0.5,
  );

  @override
  Widget build(BuildContext context) {
    final reduit = MediaQuery.disableAnimationsOf(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CouleursTaama.sable,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          _BoutonPas(
            icone: Icons.remove_rounded,
            infobulle: 'Baisser le prix de ${formaterFcfa(pas)}',
            plein: false,
            onPressed: surBaisser,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Le montant défile jusqu'au nouveau prix à chaque appui.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduit ? prix.toDouble() : 0, end: prix.toDouble()),
                    duration: reduit ? Duration.zero : const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(formaterFcfa(v.round()), style: _stylePrix),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: reduit ? Duration.zero : const Duration(milliseconds: 200),
                    child: _Ecart(key: ValueKey(ecart), ecart: ecart),
                  ),
                ],
              ),
            ),
          ),
          _BoutonPas(
            icone: Icons.add_rounded,
            infobulle: 'Monter le prix de ${formaterFcfa(pas)}',
            plein: true,
            onPressed: surMonter,
          ),
        ],
      ),
    );
  }
}

/// « Prix standard », ou l'écart dans une pastille : terre cuite à la hausse,
/// indigo à la baisse.
class _Ecart extends StatelessWidget {
  const _Ecart({super.key, required this.ecart});

  final int ecart;

  @override
  Widget build(BuildContext context) {
    if (ecart == 0) {
      return const Text(
        'Prix standard',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: CouleursTaama.grisTexte),
      );
    }
    final hausse = ecart > 0;
    final couleur = hausse ? CouleursTaama.terreCuite : CouleursTaama.indigo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hausse ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 15, color: couleur),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${hausse ? '+' : '−'}${formaterFcfa(ecart.abs())} sur le prix standard',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: couleur),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton rond : + plein (terre cuite), − en contour. Vibration légère à
/// chaque appui.
class _BoutonPas extends StatelessWidget {
  const _BoutonPas({
    required this.icone,
    required this.infobulle,
    required this.plein,
    required this.onPressed,
  });

  final IconData icone;
  final String infobulle;
  final bool plein;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final appui = onPressed;
    final actif = appui != null;
    final fond = !actif
        ? Colors.grey.shade200
        : (plein ? CouleursTaama.terreCuite : CouleursTaama.blanc);
    final couleurIcone = !actif
        ? Colors.grey.shade400
        : (plein ? CouleursTaama.blanc : CouleursTaama.indigo);
    final ombre = plein ? CouleursTaama.terreCuite : CouleursTaama.indigo;
    return Tooltip(
      message: infobulle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fond,
          border: plein || !actif
              ? null
              : Border.all(color: CouleursTaama.indigo.withValues(alpha: 0.12), width: 1.5),
          boxShadow: actif
              ? [
                  BoxShadow(
                    color: ombre.withValues(alpha: plein ? 0.35 : 0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: appui == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    appui();
                  },
            child: Icon(icone, size: 28, color: couleurIcone),
          ),
        ),
      ),
    );
  }
}
