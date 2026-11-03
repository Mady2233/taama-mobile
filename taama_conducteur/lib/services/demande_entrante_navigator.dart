import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/demande_entrante_screen.dart';
import 'sonnerie_service.dart';

/// Clé de navigation globale, câblée sur le MaterialApp (voir main.dart) —
/// nécessaire pour ouvrir un écran depuis un contexte qui n'a pas de
/// BuildContext à lui (le service de notifications FCM, en particulier).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Ouvre l'écran de demande entrante pour `demandeId`, en évitant les
/// doublons : le polling de l'espace chauffeur ET un tap sur la notification
/// FCM peuvent tous les deux déclencher la même demande quasi simultanément.
///
/// La sonnerie est liée à la vie de cet écran : elle démarre à l'ouverture
/// et s'arrête à sa fermeture (acceptée, refusée, expirée ou retour), quel
/// que soit le déclencheur (polling ou FCM). SonnerieService se coupe aussi
/// tout seul après 45 s.
class DemandeEntranteNavigator {
  static int? _idAffiche;

  // Demandes refusées pendant cette session : jamais réaffichées, même si le
  // polling les revoit (la vraie garde est côté serveur : un chauffeur qui a
  // refusé ne se voit jamais réattribuer la demande).
  static final Set<int> _idsRefuses = {};

  static void marquerRefusee(int demandeId) {
    _idsRefuses.add(demandeId);
    if (_idAffiche == demandeId || _idAffiche == null) {
      SonnerieService.instance.arreter();
    }
  }

  /// Réessaie pendant quelques secondes si le Navigator n'est pas encore
  /// monté (cas du tap sur une notification qui relance l'app depuis zéro :
  /// ce code peut s'exécuter avant que runApp() n'ait fini de construire
  /// l'arbre de widgets).
  static Future<void> afficherSiNecessaire(
    int demandeId, {
    Map<String, dynamic>? demandeInitiale,
    // false quand le chauffeur vient de toucher la notification : le
    // téléphone a déjà sonné, on ouvre l'écran en silence.
    bool sonner = true,
  }) async {
    if (_idAffiche == demandeId || _idsRefuses.contains(demandeId)) return;

    NavigatorState? navState = navigatorKey.currentState;
    var tentatives = 0;
    while (navState == null && tentatives < 20) {
      await Future.delayed(const Duration(milliseconds: 250));
      navState = navigatorKey.currentState;
      tentatives++;
    }
    if (navState == null) return;

    // Revérifié après l'attente ci-dessus : un autre déclenchement a pu
    // arriver pendant qu'on patientait pour le Navigator, ou la demande a pu
    // être refusée entre-temps.
    if (_idAffiche == demandeId || _idsRefuses.contains(demandeId)) return;
    _idAffiche = demandeId;

    if (sonner) SonnerieService.instance.demarrer();
    try {
      await navState.push(
        MaterialPageRoute(
          builder: (_) => EcranDemandeEntrante(
            demandeId: demandeId,
            demandeInitiale: demandeInitiale,
          ),
        ),
      );
    } finally {
      // Écran fermé (réponse, expiration, retour) : on coupe. Seulement si
      // c'est bien CET écran qui était au premier plan — une 2e demande
      // ouverte par-dessus garde la main sur la sonnerie.
      if (_idAffiche == demandeId) {
        _idAffiche = null;
        SonnerieService.instance.arreter();
      }
    }
  }
}
