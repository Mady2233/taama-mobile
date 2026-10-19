// lib/widgets/taama/anime_en_boucle.dart
//
// Petite animation qui tourne en boucle (clignotement, flottement, ondes).
// - S'arrête si l'utilisateur a activé « réduire les animations » (t = 0).
// - S'arrête toute seule quand l'onglet n'est pas visible (TickerMode),
//   donc pas de batterie consommée en arrière-plan.

import 'package:flutter/material.dart';

class AnimeEnBoucle extends StatefulWidget {
  const AnimeEnBoucle({
    super.key,
    required this.duree,
    required this.builder,
    this.allerRetour = true,
    this.courbe = Curves.easeInOut,
    this.child,
  });

  final Duration duree;
  final bool allerRetour;
  final Curve courbe;

  /// `t` varie de 0 à 1 (puis de 1 à 0 si [allerRetour]).
  final Widget Function(BuildContext context, double t, Widget? child) builder;
  final Widget? child;

  @override
  State<AnimeEnBoucle> createState() => _AnimeEnBoucleState();
}

class _AnimeEnBoucleState extends State<AnimeEnBoucle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controleur =
      AnimationController(vsync: this, duration: widget.duree);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controleur
        ..stop()
        ..value = 0;
    } else if (!_controleur.isAnimating) {
      _controleur.repeat(reverse: widget.allerRetour);
    }
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controleur,
      child: widget.child,
      builder: (context, child) =>
          widget.builder(context, widget.courbe.transform(_controleur.value), child),
    );
  }
}
