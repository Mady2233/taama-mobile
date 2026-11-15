// lib/services/navigation.dart
//
// Clé du Navigator de l'app (MaterialApp, main.dart) : ouvrir un écran depuis
// un service qui n'a pas de BuildContext — « Mise à jour requise » quand le
// serveur répond 426 ou au retour au premier plan (MiseAJour).
// Observateur des écrans : un écran sait quand un autre le couvre (l'accueil
// suspend alors ses requêtes périodiques).

import 'package:flutter/widgets.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final RouteObserver<ModalRoute<void>> observateurEcrans = RouteObserver<ModalRoute<void>>();
