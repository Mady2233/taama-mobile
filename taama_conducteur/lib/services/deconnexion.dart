// lib/services/deconnexion.dart
//
// Déconnexion du compte (POST /api/comptes/deconnexion/ ; côté serveur,
// accounts/deconnexion.py : toutes les sessions du compte révoquées, ses
// jetons de notification retirés, le chauffeur hors ligne).
// - course ou livraison en cours connue de l'app : refus, sans requête ;
//   réponse 409 du serveur : refus aussi. Rien n'est effacé ;
// - 200, ou 401 (session déjà révoquée) : déconnecté ;
// - toute autre issue (réseau, délai dépassé, 5xx, 426, 429…) : la session
//   de l'appareil est effacée quand même (deconnecteHorsReseau : l'écran dit
//   que les autres appareils restent connectés). L'app garde seulement l'ancien
//   jeton de session et le jeton de notification de l'appareil, pour retirer
//   ce dernier du serveur au prochain lancement (reprendre :
//   POST /api/trajets/notifications/retirer-token/), trace effacée sur 200,
//   400 ou 401. L'ancien jeton de session ne sert qu'à cette requête ;
// - ce rejeu ne révoque JAMAIS de session. Le jeton de session est unique
//   par compte et partagé par tous ses appareils et par les deux apps : un
//   rejeu tardif couperait une session ouverte depuis, sur un autre
//   téléphone ou dans l'autre app. La session non révoquée reste donc
//   valide côté serveur (dette : un jeton par appareil, CONTEXTE.md) ;
// - le jeton Firebase de l'appareil est supprimé (deleteToken, délai
//   maximal) sans faire attendre l'écran ; en cas d'échec, retenté au
//   prochain lancement. NotificationService.token repasse à nul : la
//   prochaine connexion en redemande un à Firebase.
// Reconnexion avec le même jeton de session (le serveur le réutilise tant
// qu'il ne l'a pas révoqué) : l'appareil sert de nouveau à ce compte, le
// retrait en attente est abandonné, il ôterait le jeton de notification de
// la nouvelle session (apresConnexion). Une connexion attend aussi la fin
// d'une reprise en cours.
// Fichier identique dans taama_app et taama_conducteur.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'notification_service.dart';

enum IssueDeconnexion {
  deconnecte,

  /// Déconnecté sur ce téléphone seulement : le serveur n'a pas été joint,
  /// les autres appareils du compte restent connectés.
  deconnecteHorsReseau,

  courseEnCours;

  /// La session de ce téléphone est effacée.
  bool get estDeconnecte => this != courseEnCours;
}

/// Un appareil dont le jeton de notification reste à retirer du serveur.
@immutable
class AppareilARetirer {
  const AppareilARetirer({required this.session, required this.notification});

  /// Ancien jeton de session : ne sert qu'à la requête de retrait.
  final String session;

  /// Jeton de notification (FCM) de l'appareil au moment de la déconnexion.
  final String notification;

  static AppareilARetirer? depuisTexte(String texte) {
    try {
      final donnees = jsonDecode(texte);
      if (donnees is! Map) return null;
      final session = donnees['session'];
      final notification = donnees['notification'];
      if (session is! String || session.isEmpty || notification is! String || notification.isEmpty) {
        return null;
      }
      return AppareilARetirer(session: session, notification: notification);
    } catch (_) {
      return null;
    }
  }

  String enTexte() => jsonEncode({'session': session, 'notification': notification});

  @override
  bool operator ==(Object other) =>
      other is AppareilARetirer && other.session == session && other.notification == notification;

  @override
  int get hashCode => Object.hash(session, notification);
}

class Deconnexion {
  Deconnexion._();

  static const String messageCourseEnCours = 'Termine ta course avant de te déconnecter.';

  /// Appareils dont le jeton de notification reste à retirer du serveur.
  static const String cleAppareilsARetirer = 'deconnexion_appareils_a_retirer';

  /// Le jeton Firebase de l'appareil reste à supprimer.
  static const String cleJetonFirebaseASupprimer = 'jeton_firebase_a_supprimer';

  /// Au-delà, le plus ancien retrait en attente est oublié.
  static const int maxEnAttente = 5;

  /// Supprime le jeton Firebase de l'appareil ; remplacé dans les tests.
  @visibleForTesting
  static Future<void> Function() supprimerJetonFirebase = _supprimerJetonFirebase;

  @visibleForTesting
  static Duration delaiFirebase = const Duration(seconds: 12);

  static Future<void> _supprimerJetonFirebase() => FirebaseMessaging.instance.deleteToken();

  static Future<void>? _tache;

  // Appel natif de suppression encore en route : le délai rend la main sans
  // l'annuler. Une connexion faite entre-temps redemande son jeton quand il
  // aboutit (apresConnexion), et aucun deuxième appel ne part.
  static Future<void>? _suppressionNative;

  /// Déconnecte le compte. [courseEnCoursLocale] : une course ou une
  /// livraison en cours est connue de l'app.
  static Future<IssueDeconnexion> seDeconnecter({bool courseEnCoursLocale = false}) async {
    if (courseEnCoursLocale) return IssueDeconnexion.courseEnCours;
    final jeton = ApiService.token;
    var horsReseau = false;
    if (jeton != null) {
      int? code;
      try {
        code = await ApiService.deconnexion(jeton);
      } catch (_) {
        code = null; // réseau, délai dépassé
      }
      if (code == 409) return IssueDeconnexion.courseEnCours;
      horsReseau = code != 200 && code != 401;
      // Noté avant d'effacer la session : rien ne se perd si l'app se ferme.
      final notification = NotificationService.token;
      if (horsReseau && notification != null && notification.isNotEmpty) {
        await _ajouterAppareil(
          await SharedPreferences.getInstance(),
          AppareilARetirer(session: jeton, notification: notification),
        );
      }
    }
    await effacerSessionLocale();
    return horsReseau ? IssueDeconnexion.deconnecteHorsReseau : IssueDeconnexion.deconnecte;
  }

  /// Efface la session de cet appareil, sans requête au serveur (aussi après
  /// la suppression du compte) : session et jeton de notification oubliés,
  /// jeton Firebase supprimé en arrière-plan.
  static Future<void> effacerSessionLocale() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(cleJetonFirebaseASupprimer, true);
    await ApiService.definirToken('');
    NotificationService.token = null;
    unawaited(_enFond(() => _supprimerJetonFirebaseSiNote(preferences)));
  }

  /// Reprend ce qui est resté en attente, au lancement et avant une
  /// connexion : jetons de notification à retirer du serveur (jamais de
  /// session révoquée), puis jeton Firebase à supprimer. Jamais d'exception.
  static Future<void> reprendre() => _enFond(() async {
        final preferences = await SharedPreferences.getInstance();
        await _retirerAppareilsEnAttente(preferences);
        await _supprimerJetonFirebaseSiNote(preferences);
      });

  /// Après une connexion réussie. Même jeton de session qu'un retrait en
  /// attente : l'appareil sert de nouveau à ce compte, le retrait est
  /// abandonné. Le jeton Firebase de l'appareil sert à la nouvelle session :
  /// il n'est plus à supprimer.
  static Future<void> apresConnexion() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(cleJetonFirebaseASupprimer);
      final jeton = ApiService.token;
      if (jeton != null) {
        await _garderAppareils(preferences, (a) => a.session != jeton);
      }
      // Suppression native encore en route : quand elle aboutit, le jeton
      // envoyé pour cette session est mort ; on en redemande un.
      final appel = _suppressionNative;
      if (appel != null) {
        unawaited(appel.then((_) {
          NotificationService.token = null;
          return NotificationService.reenregistrerJeton();
        }, onError: (Object _) {}));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Deconnexion] $e');
    }
  }

  /// Retraits en attente, gardés sur le téléphone (tests).
  @visibleForTesting
  static Future<List<AppareilARetirer>> appareilsEnAttente() async =>
      _lireAppareils(await SharedPreferences.getInstance());

  static Future<void> _retirerAppareilsEnAttente(SharedPreferences preferences) async {
    for (final appareil in _lireAppareils(preferences)) {
      // Session rouverte avec ce même jeton : l'appareil sert de nouveau à ce
      // compte, son jeton de notification aussi.
      if (appareil.session != ApiService.token) {
        final int code;
        try {
          code = await ApiService.retirerAppareil(appareil.session, appareil.notification);
        } catch (_) {
          return; // réseau, délai dépassé : au prochain lancement
        }
        // 200 retiré (ou déjà parti), 401 session déjà révoquée (ses jetons
        // de notification aussi), 400 jeton refusé : rien à refaire.
        if (code != 200 && code != 400 && code != 401) continue; // 5xx… : au prochain lancement
      }
      await _garderAppareils(preferences, (a) => a != appareil);
    }
  }

  static Future<void> _supprimerJetonFirebaseSiNote(SharedPreferences preferences) async {
    if (preferences.getBool(cleJetonFirebaseASupprimer) != true) return;
    // Session ouverte depuis : ce jeton est désormais le sien.
    if (ApiService.estConnecte) {
      await preferences.remove(cleJetonFirebaseASupprimer);
      return;
    }
    if (_suppressionNative != null) return; // déjà en route
    final Future<void> appel;
    try {
      appel = supprimerJetonFirebase();
    } catch (_) {
      return; // Firebase absent : au prochain lancement
    }
    _suppressionNative = appel;
    unawaited(appel.then((_) async {
      // Aboutie, même après le délai : sans session ouverte, plus rien à
      // supprimer (avec une session, apresConnexion redemande le jeton).
      if (ApiService.estConnecte) return;
      NotificationService.token = null;
      try {
        await preferences.remove(cleJetonFirebaseASupprimer);
      } catch (_) {
        // Marque restée : nouvel essai, sans effet, au prochain lancement.
      }
    }, onError: (Object _) {}).whenComplete(() {
      if (identical(_suppressionNative, appel)) _suppressionNative = null;
    }));
    try {
      await appel.timeout(delaiFirebase);
    } catch (_) {
      return; // Firebase injoignable ou trop lent : au prochain lancement
    }
    NotificationService.token = null;
    await preferences.remove(cleJetonFirebaseASupprimer);
  }

  static List<AppareilARetirer> _lireAppareils(SharedPreferences preferences) => [
        for (final texte in preferences.getStringList(cleAppareilsARetirer) ?? const <String>[])
          if (AppareilARetirer.depuisTexte(texte) case final appareil?) appareil,
      ];

  static Future<void> _ecrireAppareils(SharedPreferences preferences, List<AppareilARetirer> appareils) async {
    if (appareils.isEmpty) {
      await preferences.remove(cleAppareilsARetirer);
    } else {
      await preferences.setStringList(cleAppareilsARetirer, [for (final a in appareils) a.enTexte()]);
    }
  }

  static Future<void> _ajouterAppareil(SharedPreferences preferences, AppareilARetirer appareil) async {
    final appareils = _lireAppareils(preferences)
      ..remove(appareil)
      ..add(appareil);
    await _ecrireAppareils(
      preferences,
      appareils.length > maxEnAttente ? appareils.sublist(appareils.length - maxEnAttente) : appareils,
    );
  }

  static Future<void> _garderAppareils(SharedPreferences preferences, bool Function(AppareilARetirer) garder) async {
    final appareils = _lireAppareils(preferences);
    final gardes = appareils.where(garder).toList();
    if (gardes.length != appareils.length) await _ecrireAppareils(preferences, gardes);
  }

  /// Une tâche de fond à la fois, dans l'ordre d'arrivée.
  static Future<void> _enFond(Future<void> Function() tache) {
    final precedente = _tache;
    Future<void> suivante() async {
      if (precedente != null) await precedente;
      try {
        await tache();
      } catch (e) {
        if (kDebugMode) debugPrint('[Deconnexion] $e');
      }
    }

    return _tache = suivante();
  }

  /// Fin des tâches de fond (tests).
  @visibleForTesting
  static Future<void> get tachesTerminees => _tache ?? Future<void>.value();

  @visibleForTesting
  static void reinitialiser() {
    supprimerJetonFirebase = _supprimerJetonFirebase;
    delaiFirebase = const Duration(seconds: 12);
    _tache = null;
    _suppressionNative = null;
  }
}
