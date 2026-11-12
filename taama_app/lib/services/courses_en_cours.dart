// lib/services/courses_en_cours.dart
//
// Courses et livraisons en cours connues de l'app, gardées sur le téléphone :
// tant qu'il en reste une, la déconnexion est refusée sans requête
// (Deconnexion), même hors réseau.
// - enregistrée à sa création, et quand l'accueil retrouve une course en
//   cours sur le serveur ;
// - effacée quand son suivi la reçoit terminée ou annulée (livrée ou
//   annulée), et quand l'accueil ne trouve plus de course en cours ;
// - expiration de sécurité : 2 h après son enregistrement, elle ne compte
//   plus. Une fin manquée (app fermée) ne bloque pas la déconnexion pour
//   toujours ;
// - avant de refuser une déconnexion, chacune est relue sur le serveur
//   (enCoursApresRelecture) : un suivi quitté avant la fin ne peut plus
//   l'effacer, et une livraison ne se rouvre pas.
// Jamais d'exception : un téléphone qui refuse d'écrire ne bloque ni une
// commande ni une déconnexion.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class CoursesEnCours {
  CoursesEnCours._();

  @visibleForTesting
  static const String cle = 'courses_en_cours';

  static const Duration expiration = Duration(hours: 2);

  // Statuts qui bloquent la déconnexion côté serveur (accounts/deconnexion.py).
  // Une livraison ne compte qu'une fois attribuée à un livreur : encore en
  // recherche, elle ne bloque jamais.
  static const Set<String> _statutsCourseEnCours = {
    'en_recherche', 'chauffeur_trouve', 'contre_offre', 'en_route', 'client_a_bord',
  };
  static const Set<String> _statutsLivraisonEnCours = {
    'livreur_assigne', 'en_collecte', 'en_livraison',
  };

  static Future<void> enregistrerCourse(int id, {DateTime? maintenant}) =>
      _modifier(maintenant, (entrees, instant) => entrees['course:$id'] = instant);

  static Future<void> enregistrerLivraison(int id, {DateTime? maintenant}) =>
      _modifier(maintenant, (entrees, instant) => entrees['livraison:$id'] = instant);

  static Future<void> effacerCourse(int id) => _modifier(null, (entrees, _) => entrees.remove('course:$id'));

  static Future<void> effacerLivraison(int id) =>
      _modifier(null, (entrees, _) => entrees.remove('livraison:$id'));

  /// L'accueil a relu les courses sur le serveur à [lueLe] : seule [id] est
  /// en cours (aucune si nul). Une course enregistrée depuis (commandée
  /// pendant la lecture) est gardée ; les livraisons ne changent pas.
  static Future<void> remplacerCourses(int? id, {required DateTime lueLe, DateTime? maintenant}) =>
      _modifier(maintenant, (entrees, instant) {
        entrees.removeWhere((cle, le) => cle.startsWith('course:') && le.isBefore(lueLe));
        if (id != null) entrees['course:$id'] = instant;
      });

  static Future<void> toutEffacer() => _modifier(null, (entrees, _) => entrees.clear());

  /// Une course ou une livraison est en cours (enregistrée il y a moins de 2 h).
  static Future<bool> enCours({DateTime? maintenant}) async {
    final instant = maintenant ?? DateTime.now();
    try {
      final preferences = await SharedPreferences.getInstance();
      return _lire(preferences).values.any((le) => _valide(le, instant));
    } catch (_) {
      return false;
    }
  }

  /// Comme [enCours], après relecture sur le serveur de chaque course ou
  /// livraison connue ici : celle qu'il dit finie est effacée. Sans réponse
  /// (réseau, délai de 12 s), elle compte toujours : jamais de déconnexion
  /// pendant une course faute de réseau. Rien de connu : aucune requête.
  static Future<bool> enCoursApresRelecture({DateTime? maintenant}) async {
    final instant = maintenant ?? DateTime.now();
    Map<String, DateTime> entrees;
    try {
      entrees = _lire(await SharedPreferences.getInstance());
    } catch (_) {
      return false;
    }
    for (final MapEntry(key: cle, value: le) in entrees.entries) {
      if (!_valide(le, instant)) continue;
      final course = cle.startsWith('course:');
      final id = int.tryParse(cle.substring(cle.indexOf(':') + 1));
      if (id == null) continue;
      try {
        final detail = await (course ? ApiService.detailDemande(id) : ApiService.detailCourier(id))
            .timeout(const Duration(seconds: 12));
        final statut = detail['statut'];
        final enCours = course ? _statutsCourseEnCours : _statutsLivraisonEnCours;
        if (statut is String && statut.isNotEmpty && !enCours.contains(statut)) {
          await _modifier(instant, (e, _) => e.remove(cle));
        }
      } catch (_) {
        // Sans réponse : elle compte toujours.
      }
    }
    return enCours(maintenant: instant);
  }

  // Horloge reculée : une date dans le futur expire de même.
  static bool _valide(DateTime le, DateTime instant) => instant.difference(le).abs() < expiration;

  static Future<void> _modifier(
    DateTime? maintenant,
    void Function(Map<String, DateTime> entrees, DateTime instant) changement,
  ) async {
    final instant = maintenant ?? DateTime.now();
    try {
      final preferences = await SharedPreferences.getInstance();
      final entrees = _lire(preferences)..removeWhere((_, le) => !_valide(le, instant));
      changement(entrees, instant);
      if (entrees.isEmpty) {
        await preferences.remove(cle);
      } else {
        await preferences.setString(
          cle,
          jsonEncode(entrees.map((cle, le) => MapEntry(cle, le.toIso8601String()))),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CoursesEnCours] Non gardé : $e');
    }
  }

  static Map<String, DateTime> _lire(SharedPreferences preferences) {
    final entrees = <String, DateTime>{};
    final brut = preferences.getString(cle);
    if (brut == null) return entrees;
    try {
      final carte = jsonDecode(brut);
      if (carte is Map) {
        carte.forEach((cle, valeur) {
          final le = DateTime.tryParse(valeur?.toString() ?? '');
          if (cle is String && le != null) entrees[cle] = le;
        });
      }
    } catch (_) {
      // Valeur illisible : rien n'est connu.
    }
    return entrees;
  }
}
