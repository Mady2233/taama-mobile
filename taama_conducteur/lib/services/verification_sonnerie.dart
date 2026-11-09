// lib/services/verification_sonnerie.dart
//
// Ce qui peut empêcher une demande de sonner, lu sur le téléphone :
// notifications des demandes coupées, mode silencieux ou vibreur, économie de
// batterie (Tecno, Infinix, Itel coupent les apps en arrière-plan, la
// notification n'arrive plus). Rien n'est envoyé au serveur. Ce qui ne peut
// pas être lu n'est jamais signalé : pas d'alerte inventée.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'sonnerie_notification.dart';

enum ProblemeSonnerie { notificationsCoupees, sonnerieMuette, economieBatterie }

class VerificationSonnerie {
  VerificationSonnerie._();

  /// Côté Android : MainActivity.kt.
  static const MethodChannel _canal = MethodChannel('taama/sonnerie_systeme');

  /// Lecture de ce que le téléphone a répondu ; null : inconnu, non signalé.
  static List<ProblemeSonnerie> lire({
    required bool? notificationsActives,
    required Importance? importanceCanal,
    required Map<String, bool>? etatSysteme,
  }) =>
      [
        if (notificationsActives == false ||
            (importanceCanal != null && importanceCanal.value < Importance.high.value))
          ProblemeSonnerie.notificationsCoupees,
        if (etatSysteme?['sonnerieMuette'] == true) ProblemeSonnerie.sonnerieMuette,
        if (etatSysteme?['economieBatterie'] == true) ProblemeSonnerie.economieBatterie,
      ];

  static Future<List<ProblemeSonnerie>> verifier() async {
    if (defaultTargetPlatform != TargetPlatform.android) return const [];
    bool? actives;
    Importance? importance;
    Map<String, bool>? etat;
    try {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      actives = await android?.areNotificationsEnabled();
      final canaux = await android?.getNotificationChannels();
      for (final canal in canaux ?? const <AndroidNotificationChannel>[]) {
        if (canal.id == SonnerieNotification.idCanal) importance = canal.importance;
      }
    } catch (_) {
      // Illisible : non signalé.
    }
    try {
      etat = await _canal.invokeMapMethod<String, bool>('etat').timeout(const Duration(seconds: 2));
    } catch (_) {
      // Illisible : non signalé.
    }
    return lire(notificationsActives: actives, importanceCanal: importance, etatSysteme: etat);
  }

  /// Ouvre l'écran de réglages qui corrige [probleme]. Faux si aucun écran
  /// de réglages n'a pu s'ouvrir.
  static Future<bool> corriger(ProblemeSonnerie probleme) async {
    final reglage = switch (probleme) {
      ProblemeSonnerie.notificationsCoupees => 'notifications',
      ProblemeSonnerie.sonnerieMuette => 'son',
      ProblemeSonnerie.economieBatterie => 'batterie',
    };
    try {
      return await _canal.invokeMethod<bool>('ouvrirReglages', {'reglage': reglage}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
