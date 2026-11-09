// lib/services/sonnerie_notification.dart
//
// Demande de course reçue téléphone verrouillé ou app en arrière-plan : la
// notification sonne en boucle, comme un appel, jusqu'à la réponse du
// chauffeur (45 s au plus). Avant, Android ne jouait la sonnerie qu'une fois,
// écran éteint : le chauffeur ne l'entendait pas.
//
// Elle remplace la notification affichée par FCM (son unique, ancien canal) :
// même identifiant Android, id 0 et tag « demande_<id> » posé par le serveur
// (trajets/notifications.py). Si le remplacement échoue, celle de FCM reste
// et sonne au moins une fois. Le serveur n'a rien à changer : les anciennes
// versions de l'app gardent leur comportement.

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../theme/couleurs_taama.dart';
import 'sonnerie_service.dart';

class SonnerieNotification {
  SonnerieNotification._();

  /// Nouvel identifiant : Android fige le son et le flux audio d'un canal à
  /// sa création, l'ancien (taama_demandes_course) ne peut pas devenir une
  /// sonnerie.
  static const String idCanal = 'taama_demandes_course_v2';

  /// Identifiant Android de la notification de FCM : toujours 0, distinguée
  /// par son tag.
  static const int _idNotification = 0;

  /// Notification.FLAG_INSISTENT : le son se répète jusqu'à ce que la
  /// notification soit touchée, balayée, retirée ou le volet ouvert.
  static const int flagInsistent = 4;

  static const String _prefixePayload = 'nouvelle_demande:';

  static const RawResourceAndroidNotificationSound _son =
      RawResourceAndroidNotificationSound('sonnerie_course');

  /// Flux « sonnerie » : suit le volume de sonnerie du téléphone, comme un
  /// appel entrant (et comme SonnerieService, app ouverte).
  static final AndroidNotificationChannel canal = AndroidNotificationChannel(
    idCanal,
    'Demandes de course (sonnerie)',
    description: 'Sonne comme un appel, même téléphone verrouillé, jusqu’à ta réponse',
    importance: Importance.max,
    playSound: true,
    sound: _son,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 600, 300, 600, 300, 600]),
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
  );

  static String tag(int demandeId) => 'demande_$demandeId';

  static String payload(int demandeId) => '$_prefixePayload$demandeId';

  /// Demande ouverte par un toucher sur la notification ; null pour toute
  /// autre notification.
  static int? demandeDepuisPayload(String? payload) {
    if (payload == null || !payload.startsWith(_prefixePayload)) return null;
    return int.tryParse(payload.substring(_prefixePayload.length));
  }

  @visibleForTesting
  static AndroidNotificationDetails details(int demandeId) => AndroidNotificationDetails(
        idCanal,
        canal.name,
        channelDescription: canal.description,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        // Visible écran verrouillé : le serveur n'y met ni nom ni numéro du
        // client (prix, destination, type de véhicule).
        visibility: NotificationVisibility.public,
        playSound: true,
        sound: _son,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        enableVibration: true,
        vibrationPattern: canal.vibrationPattern,
        additionalFlags: Int32List.fromList([flagInsistent]),
        // Jamais de sonnerie sans fin : même limite qu'app ouverte.
        timeoutAfter: SonnerieService.dureeMax.inMilliseconds,
        tag: tag(demandeId),
        autoCancel: true,
        color: CouleursTaama.terreCuite,
        ticker: 'Nouvelle demande de course',
      );

  /// Fait sonner la demande. Appelé par le gestionnaire FCM d'arrière-plan.
  static Future<void> sonner(
    FlutterLocalNotificationsPlugin plugin, {
    required int demandeId,
    String? titre,
    String? texte,
  }) async {
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(canal);
    await plugin.show(
      _idNotification,
      titre ?? 'Nouvelle course',
      texte ?? 'Touche pour voir la demande',
      NotificationDetails(android: details(demandeId)),
      payload: payload(demandeId),
    );
  }

  /// Coupe la sonnerie de cette demande : écran de demande ouvert (la
  /// sonnerie de l'app prend le relais), demande annulée. Sans effet si elle
  /// ne sonne pas ; un échec ne bloque rien (45 s au plus de toute façon).
  static Future<void> arreter(int demandeId, {FlutterLocalNotificationsPlugin? plugin}) async {
    try {
      await (plugin ?? FlutterLocalNotificationsPlugin()).cancel(_idNotification, tag: tag(demandeId));
    } catch (_) {
      // Plateforme sans notifications (tests) ou plugin indisponible.
    }
  }
}
