import 'dart:async';

/// Rafraîchissement périodique, suspendu quand l'app n'est plus à l'écran.
/// Au retour, l'action repart tout de suite : l'écran n'affiche jamais un état
/// vieux d'un intervalle.
class PollingPremierPlan {
  PollingPremierPlan({required this.intervalle, required this.action});

  final Duration intervalle;
  final Future<void> Function() action;
  Timer? _timer;

  bool get actif => _timer != null;

  void demarrer() {
    _timer?.cancel();
    _timer = Timer.periodic(intervalle, (_) => action());
  }

  void suspendre() {
    _timer?.cancel();
    _timer = null;
  }

  void reprendre() {
    if (actif) return;
    action();
    demarrer();
  }
}
