// lib/services/fin_de_session.dart
//
// Fin de session : le serveur répond 401 à une requête envoyée avec la session
// ouverte de ce téléphone. Elle a été fermée ailleurs : déconnexion sur un
// autre appareil ou dans l'autre app Taama (le jeton est partagé par compte),
// compte supprimé. La session de ce téléphone est effacée
// (Deconnexion.effacerSessionLocale), puis l'app revient à l'écran de
// connexion avec un message. Une seule fois.
// Toutes les requêtes passent par ClientSession (main.dart,
// http.runWithClient) : un seul endroit, quel que soit l'appel. Jamais pour :
// - un autre hôte que l'API Taama (ApiConfig.baseUrl : schéma, hôte, port) :
//   un 401 d'OSRM, des tuiles, du stockage ou de Firebase ne dit rien de la
//   session ;
// - une autre session : la reprise d'une déconnexion différée part avec
//   l'ancien jeton, son 401 ne dit rien de la session ouverte ;
// - la déconnexion et la suppression du compte, dont l'écran traite le 401
//   lui-même (« déjà déconnecté », « déjà supprimé ») ; pendant ces
//   opérations (pendant), un 401 d'une autre requête non plus : l'écran garde
//   la main sur son issue et son message ;
// - l'écran « Mise à jour requise » affiché : la session est effacée, l'écran
//   reste (il mène ensuite au démarrage, donc à la connexion).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../screens/connexion_screen.dart';
import 'api_service.dart';
import 'deconnexion.dart';
import 'demande_entrante_navigator.dart' show navigatorKey;
import 'mise_a_jour.dart';

/// Affiché à l'écran de connexion après une fin de session.
const String messageSessionFermee = 'Tu as été déconnecté de Taama. Reconnecte-toi pour continuer.';

/// Origine de l'API Taama : seule elle peut fermer la session.
final String _origineApi = Uri.parse(ApiConfig.baseUrl).origin;

/// Chemins dont l'écran traite le 401 lui-même.
const List<String> _cheminsSansFinDeSession = ['/comptes/deconnexion/', '/comptes/supprimer-mon-compte/'];

class FinDeSession {
  FinDeSession._();

  static bool _enCours = false;
  static int _operationsDeCompte = 0;
  static bool _fermeeDuranteOperation = false;

  /// Opération de compte (suppression, déconnexion) : tant qu'elle dure, un
  /// 401 d'une autre requête (polling de l'écran du dessous) ne ferme pas la
  /// session. Le serveur l'a peut-être déjà révoquée : c'est l'écran qui
  /// conclut, avec son propre message.
  static Future<T> pendant<T>(Future<T> Function() operation) async {
    if (_operationsDeCompte == 0) _fermeeDuranteOperation = false;
    _operationsDeCompte++;
    try {
      return await operation();
    } finally {
      _operationsDeCompte--;
    }
  }

  @visibleForTesting
  static bool Function() ecranBloquantAffiche = _ecranBloquantAffiche;

  static bool _ecranBloquantAffiche() => MiseAJour.ecranAffiche;

  /// Un 401 de la session ouverte est arrivé pendant la dernière opération de
  /// compte : le serveur l'a déjà fermée (compte supprimé). Une suppression
  /// dont la réponse s'est perdue a donc abouti.
  static bool get fermeeDuranteOperation => _fermeeDuranteOperation;

  /// Un 401 a répondu à une requête envoyée avec le jeton de session [jeton].
  static void signaler(String jeton) {
    if (_enCours || jeton.isEmpty || jeton != ApiService.token) return;
    if (_operationsDeCompte > 0) {
      _fermeeDuranteOperation = true; // l'écran conclut
      return;
    }
    _enCours = true;
    unawaited(_fermer().whenComplete(() => _enCours = false));
  }

  static Future<void> _fermer() async {
    try {
      await Deconnexion.effacerSessionLocale();
    } catch (e) {
      if (kDebugMode) debugPrint('[FinDeSession] $e');
    }
    if (ecranBloquantAffiche()) return;
    final navigateur = navigatorKey.currentState;
    // Pas encore d'écran : le démarrage mènera à la connexion.
    if (navigateur == null) return;
    final contexte = navigateur.context;
    if (!contexte.mounted) return;
    final messager = ScaffoldMessenger.maybeOf(contexte);
    unawaited(navigateur.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EcranConnexion()),
      (_) => false,
    ));
    // L'écran a peut-être déjà affiché son erreur : un seul message.
    messager
      ?..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text(messageSessionFermee)));
  }

  /// Fin de session en cours (tests).
  @visibleForTesting
  static bool get enCours => _enCours;

  @visibleForTesting
  static void reinitialiser() {
    _enCours = false;
    _operationsDeCompte = 0;
    _fermeeDuranteOperation = false;
    ecranBloquantAffiche = _ecranBloquantAffiche;
  }
}

/// Client HTTP de l'app (main.dart) : repère les 401 de la session ouverte.
class ClientSession extends http.BaseClient {
  ClientSession(this._interne);

  /// Fabrique pour http.runWithClient : le client par défaut, enveloppé.
  static http.Client creer() => ClientSession(http.Client());

  final http.Client _interne;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest requete) async {
    final reponse = await _interne.send(requete);
    if (reponse.statusCode == 401) {
      final autorisation = requete.headers['Authorization'] ?? '';
      final chemin = requete.url.path;
      if (requete.url.origin == _origineApi &&
          autorisation.startsWith('Token ') &&
          !_cheminsSansFinDeSession.any(chemin.endsWith)) {
        FinDeSession.signaler(autorisation.substring('Token '.length));
      }
    }
    return reponse;
  }

  @override
  void close() => _interne.close();
}
