import 'dart:async';

/// Signal « le client a annulé cette course », pour l'écran de navigation. Deux
/// sources : le push `demande_annulee`, et le rafraîchissement de l'accueil en
/// secours (push perdu, app revenue au premier plan).
class AnnulationsCourse {
  AnnulationsCourse._();

  static final StreamController<int> _flux = StreamController<int>.broadcast();

  static Stream<int> get flux => _flux.stream;

  static void signaler(int demandeId) => _flux.add(demandeId);
}
