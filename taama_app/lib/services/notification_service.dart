import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'enregistrement_jeton.dart';

/// Canal Android dédié aux notifications de course — importance MAX (son +
/// pop-up "heads-up") pour que le passager soit alerté même téléphone
/// verrouillé/app fermée (conducteur trouvé, arrivée, etc.). Référencé
/// également côté backend (envoyer_notification, trajets/notifications.py)
/// et dans AndroidManifest.xml (canal par défaut FCM) : les trois doivent
/// rester alignés sur le même identifiant 'taama_notifications'.
const AndroidNotificationChannel _canalNotificationsTaama =
    AndroidNotificationChannel(
  'taama_notifications',
  'Notifications Taama',
  description: 'Suivi de course et messages importants',
  importance: Importance.max,
  playSound: true,
);

/// Handler de messages FCM reçus alors que l'app est en arrière-plan ou
/// tuée. Doit être une fonction top-level (pas une méthode de classe) avec
/// cette annotation exacte — exigé par le plugin firebase_messaging pour
/// pouvoir relancer un isolate Dart dédié en dehors du cycle de vie normal
/// de l'app. Ne fait rien de plus ici : pour un message avec un bloc
/// `notification` (toujours le cas, voir envoyer_notification côté
/// backend), Android/iOS affichent déjà la notification système
/// automatiquement, sans code Dart — ce handler existe pour respecter le
/// contrat du plugin et garder la porte ouverte à un traitement futur.
@pragma('vm:entry-point')
Future<void> gestionnaireMessageArrierePlan(RemoteMessage message) async {}

/// Gère tout ce qui concerne les notifications push :
/// - Demande de permission à l'utilisateur
/// - Récupération du token FCM (pour l'envoyer ensuite au backend)
/// - Affichage des notifications quand l'app est ouverte au premier plan
///   (par défaut, Firebase n'affiche rien automatiquement si l'app est ouverte,
///   il faut le faire nous-mêmes avec flutter_local_notifications)
class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _notificationsLocales =
      FlutterLocalNotificationsPlugin();

  /// Le token FCM de cet appareil, récupéré après initialisation.
  /// Utilisé par les écrans de connexion pour l'envoyer au backend.
  static String? token;

  /// Demande le jeton à Firebase ; remplacé dans les tests.
  @visibleForTesting
  static Future<String?> Function() demanderJeton = () => FirebaseMessaging.instance.getToken();

  /// Réenregistre le jeton sur le serveur (EnregistrementJeton). Jeton encore
  /// inconnu (Firebase muet au démarrage) : il est redemandé à Firebase.
  static Future<void> reenregistrerJeton() async {
    if (!ApiService.estConnecte) return;
    var jeton = token;
    if (jeton == null) {
      try {
        jeton = await demanderJeton().timeout(const Duration(seconds: 12));
      } catch (_) {
        return; // Firebase injoignable : nouvel essai au prochain retour
      }
      if (jeton == null) return;
      token = jeton;
    }
    await EnregistrementJeton.enregistrer(jeton);
  }

  static DateTime? _dernierEssaiAuRetour;
  static const Duration intervalleRetour = Duration(minutes: 2);

  /// Retour au premier plan : seulement si le dernier enregistrement n'a pas
  /// réussi (jamais tenté, ou abandonné faute de réseau), au plus toutes les
  /// [intervalleRetour].
  static Future<void> reenregistrerSiEchec({DateTime? maintenant}) async {
    if (!EnregistrementJeton.aReessayer) return;
    final instant = maintenant ?? DateTime.now();
    final dernier = _dernierEssaiAuRetour;
    if (dernier != null && instant.difference(dernier) < intervalleRetour) return;
    _dernierEssaiAuRetour = instant;
    await reenregistrerJeton();
  }

  @visibleForTesting
  static void reinitialiserJeton() {
    token = null;
    _dernierEssaiAuRetour = null;
    demanderJeton = () => FirebaseMessaging.instance.getToken();
  }

  static Future<void> initialiser() async {
    // 1. Je demande la permission d'envoyer des notifications (obligatoire sur iOS,
    // et recommandé sur Android 13+)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Je configure l'affichage des notifications locales (pour le premier plan)
    //    et je crée le canal haute-importance AVANT toute notification —
    //    sinon la toute première notification reçue app fermée tomberait
    //    sur le canal par défaut (silencieux, pas de heads-up).
    if (!kIsWeb) {
      const parametresAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const parametres = InitializationSettings(android: parametresAndroid);
      await _notificationsLocales.initialize(parametres);
      await _notificationsLocales
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_canalNotificationsTaama);
    }

    // 2bis. Handler des messages reçus app en arrière-plan/tuée (voir
    // gestionnaireMessageArrierePlan ci-dessus) — DOIT être enregistré tôt,
    // avant que le premier message puisse arriver.
    FirebaseMessaging.onBackgroundMessage(gestionnaireMessageArrierePlan);

    // 3. Je récupère le token de cet appareil
    try {
      token = await _messaging.getToken();
      // Le token identifie l'appareil : jamais dans les logs en production.
      if (kDebugMode) debugPrint('Token FCM récupéré : $token');
    } catch (e) {
      debugPrint('Erreur lors de la récupération du token FCM : $e');
    }

    // 4. J'écoute les notifications reçues quand l'app est ouverte au premier plan
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Notification reçue au premier plan : ${message.notification?.title}');
      _afficherNotificationLocale(message);
    });

    // 5. Si le token change (rare mais possible), je le garde à jour ET je
    // le renvoie au backend — sinon DeviceToken reste sur l'ancien token
    // (mort dès la rotation), et le passager arrête silencieusement de
    // recevoir des notifications. Réponse vérifiée, nouveaux essais
    // espacés : EnregistrementJeton.
    _messaging.onTokenRefresh.listen((nouveauToken) {
      token = nouveauToken;
      if (kDebugMode) debugPrint('Token FCM mis à jour : $nouveauToken');
      unawaited(EnregistrementJeton.enregistrer(nouveauToken));
    });
  }

  static Future<void> _afficherNotificationLocale(RemoteMessage message) async {
    if (kIsWeb) return; // Le web gère ça différemment, on simplifie pour l'instant

    const details = AndroidNotificationDetails(
      'taama_notifications', // ID du canal
      'Notifications Taama',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _notificationsLocales.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // ID unique basé sur l'heure
      message.notification?.title ?? 'Taama',
      message.notification?.body ?? '',
      const NotificationDetails(android: details),
    );
  }
}