import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/demande_entrante_screen.dart';

/// Clé de navigation globale, câblée sur le MaterialApp (voir main.dart) —
/// nécessaire pour ouvrir un écran depuis un contexte qui n'a pas de
/// BuildContext à lui (le service de notifications FCM, en particulier).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Ouvre l'écran de demande entrante pour `demandeId`, en évitant les
/// doublons : le polling de l'espace chauffeur ET un tap sur la notification
/// FCM peuvent tous les deux déclencher la même demande quasi simultanément.
class DemandeEntranteNavigator {
  static int? _idAffiche;

  /// Réessaie pendant quelques secondes si le Navigator n'est pas encore
  /// monté (cas du tap sur une notification qui relance l'app depuis zéro :
  /// ce code peut s'exécuter avant que runApp() n'ait fini de construire
  /// l'arbre de widgets).
  static Future<void> afficherSiNecessaire(
    int demandeId, {
    Map<String, dynamic>? demandeInitiale,
  }) async {
    if (_idAffiche == demandeId) return;

    NavigatorState? navState = navigatorKey.currentState;
    var tentatives = 0;
    while (navState == null && tentatives < 20) {
      await Future.delayed(const Duration(milliseconds: 250));
      navState = navigatorKey.currentState;
      tentatives++;
    }
    if (navState == null) return;

    // Revérifié après l'attente ci-dessus : un autre déclenchement a pu
    // arriver pendant qu'on patientait pour le Navigator.
    if (_idAffiche == demandeId) return;
    _idAffiche = demandeId;

    await navState.push(
      MaterialPageRoute(
        builder: (_) => EcranDemandeEntrante(
          demandeId: demandeId,
          demandeInitiale: demandeInitiale,
        ),
      ),
    );

    if (_idAffiche == demandeId) _idAffiche = null;
  }
}
