import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

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

  static Future<void> initialiser() async {
    // 1. Je demande la permission d'envoyer des notifications (obligatoire sur iOS,
    // et recommandé sur Android 13+)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Je configure l'affichage des notifications locales (pour le premier plan)
    if (!kIsWeb) {
      const parametresAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const parametres = InitializationSettings(android: parametresAndroid);
      await _notificationsLocales.initialize(parametres);
    }

    // 3. Je récupère le token de cet appareil
    try {
      token = await _messaging.getToken();
      debugPrint('Token FCM récupéré : $token');
    } catch (e) {
      debugPrint('Erreur lors de la récupération du token FCM : $e');
    }

    // 4. J'écoute les notifications reçues quand l'app est ouverte au premier plan
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Notification reçue au premier plan : ${message.notification?.title}');
      _afficherNotificationLocale(message);
    });

    // 5. Si le token change (rare mais possible), je le garde à jour
    _messaging.onTokenRefresh.listen((nouveauToken) {
      token = nouveauToken;
      debugPrint('Token FCM mis à jour : $nouveauToken');
      // Idéalement, on renverrait ce nouveau token au backend ici aussi.
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