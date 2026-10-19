// lib/widgets/taama/tuile_service.dart
//
// Tuile carrée d'un service (Moto, Voiture, Colis, Réserver) qui s'enfonce
// légèrement sous le doigt.

import 'package:flutter/material.dart';

import '../../theme/taama_theme.dart';

class TuileService extends StatefulWidget {
  const TuileService({
    super.key,
    required this.icone,
    required this.libelle,
    required this.onTap,
    this.sousTitre,
    this.miseEnAvant = false,
    this.couleurIcone,
  });

  final IconData icone;
  final String libelle;

  /// Ex. « dès 1 500 F » — uniquement une valeur fournie par le serveur.
  final String? sousTitre;
  final VoidCallback? onTap;
  final bool miseEnAvant;
  final Color? couleurIcone;

  @override
  State<TuileService> createState() => _TuileServiceState();
}

class _TuileServiceState extends State<TuileService> {
  bool _appuye = false;

  @override
  Widget build(BuildContext context) {
    final fond = widget.miseEnAvant ? TaamaColors.primary : TaamaColors.primarySoft;
    final texte = widget.miseEnAvant ? Colors.white : TaamaColors.navy;
    final icone = widget.couleurIcone ??
        (widget.miseEnAvant ? Colors.white : TaamaColors.primary);

    return AnimatedScale(
      scale: _appuye ? 0.93 : 1,
      duration: const Duration(milliseconds: 120),
      child: Material(
        color: fond,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _appuye = v),
          child: SizedBox(
            height: 88,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icone, size: 28, color: icone),
                const SizedBox(height: 6),
                Text(
                  widget.libelle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TaamaText.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: texte,
                  ),
                ),
                if (widget.sousTitre != null)
                  Text(
                    widget.sousTitre!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TaamaText.body.copyWith(
                      fontSize: 10.5,
                      color: widget.miseEnAvant
                          ? TaamaColors.primarySoft
                          : TaamaColors.textSecondary,
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
