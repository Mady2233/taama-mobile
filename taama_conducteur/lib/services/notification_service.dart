import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'demande_entrante_navigator.dart';

/// Canal Android dédié aux demandes de course — importance MAX (son +
/// pop-up "heads-up") pour que le conducteur soit alerté même téléphone
/// verrouillé/app fermée, comme un appel entrant. Référencé également côté
/// backend (envoyer_notification, trajets/notifications.py) et dans
/// AndroidManifest.xml (canal par défaut FCM) : les trois doivent rester
/// alignés sur le même identifiant 'taama_notifications'.
const AndroidNotificationChannel _canalNotificationsTaama =
    AndroidNotificationChannel(
  'taama_notifications',
  'Notifications Taama',
  description: 'Nouvelles demandes de course et messages importants',
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
    //    sinon la toute première demande de course reçue app fermée
    //    tomberait sur le canal par défaut (silencieux, pas de heads-up).
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
      debugPrint('Token FCM récupéré : $token');
    } catch (e) {
      debugPrint('Erreur lors de la récupération du token FCM : $e');
    }

    // 4. J'écoute les notifications reçues quand l'app est ouverte au premier plan
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Notification reçue au premier plan : ${message.notification?.title}');
      _afficherNotificationLocale(message);
      _traiterDonneesNotification(message.data);
    });

    // 4bis. L'utilisateur tape la notification alors que l'app était en
    // arrière-plan (pas tuée) : Firebase relance ce listener au retour au
    // premier plan avec le message qui a été tapé.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _traiterDonneesNotification(message.data);
    });

    // 4ter. L'app était tuée et a été relancée par un tap sur la
    // notification : le message qui a servi à la relancer est récupéré ici.
    final messageInitial = await _messaging.getInitialMessage();
    if (messageInitial != null) {
      _traiterDonneesNotification(messageInitial.data);
    }

    // 5. Si le token change (rare mais possible), je le garde à jour ET je
    // le renvoie au backend — sinon DeviceToken reste sur l'ancien token
    // (mort dès la rotation), et le conducteur arrête silencieusement de
    // recevoir des notifications jusqu'à sa prochaine connexion (seul autre
    // point d'enregistrement, voir otp_verification_screen.dart). Best-effort
    // (try/catch) : ApiService.enregistrerTokenNotification échoue déjà en
    // silence en interne, ce try/catch protège contre toute autre erreur.
    _messaging.onTokenRefresh.listen((nouveauToken) async {
      token = nouveauToken;
      debugPrint('Token FCM mis à jour : $nouveauToken');
      try {
        await ApiService.enregistrerTokenNotification(nouveauToken);
      } catch (e) {
        debugPrint('Erreur ré-enregistrement du token FCM : $e');
      }
    });
  }

  /// Ouvre l'écran de demande entrante si ces données FCM correspondent à
  /// une nouvelle demande instantanée assignée — que l'app soit au premier
  /// plan (onMessage), relancée depuis l'arrière-plan (onMessageOpenedApp)
  /// ou depuis un état tué (getInitialMessage). Ignore silencieusement tout
  /// autre type de notification (chat, annulation, etc.).
  static void _traiterDonneesNotification(Map<String, dynamic> donnees) {
    if (donnees['type'] != 'nouvelle_demande') return;
    final demandeId = int.tryParse(donnees['demande_id']?.toString() ?? '');
    if (demandeId == null) return;
    DemandeEntranteNavigator.afficherSiNecessaire(demandeId);
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