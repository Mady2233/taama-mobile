import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'demande_entrante_navigator.dart';

/// Canal Android général (messages, annulations…). Référencé également côté
/// backend (envoyer_notification, trajets/notifications.py) et dans
/// AndroidManifest.xml (canal par défaut FCM) : les trois doivent rester
/// alignés sur le même identifiant 'taama_notifications'.
const AndroidNotificationChannel _canalNotificationsTaama =
    AndroidNotificationChannel(
  'taama_notifications',
  'Notifications Taama',
  description: 'Messages et informations importantes',
  importance: Importance.max,
  playSound: true,
);

/// Identifiant du canal des demandes de course. Doit être IDENTIQUE à celui
/// envoyé par le backend pour les notifications `nouvelle_demande`
/// (android.notification.channel_id).
const String idCanalDemandesCourse = 'taama_demandes_course';

/// Canal dédié aux demandes de course : sonnerie Taama (fichier
/// android/app/src/main/res/raw/sonnerie_course.wav), vibration longue,
/// importance MAX (pop-up même téléphone verrouillé), comme un appel.
///
/// Canal distinct de 'taama_notifications' : Android fige le son d'un canal à
/// sa création — modifier celui d'un canal déjà installé n'a aucun effet sur
/// les téléphones des chauffeurs. Pour changer de sonnerie plus tard, il
/// faudra donc un NOUVEL identifiant (ex. 'taama_demandes_course_v2').
final AndroidNotificationChannel _canalDemandesCourse = AndroidNotificationChannel(
  idCanalDemandesCourse,
  'Demandes de course',
  description: 'Sonnerie quand un client te demande une course',
  importance: Importance.max,
  playSound: true,
  sound: const RawResourceAndroidNotificationSound('sonnerie_course'),
  enableVibration: true,
  vibrationPattern: Int64List.fromList([0, 600, 300, 600, 300, 600]),
);

/// Handler de messages FCM reçus alors que l'app est en arrière-plan ou
/// tuée. Doit être une fonction top-level (pas une méthode de classe) avec
/// cette annotation exacte — exigé par le plugin firebase_messaging pour
/// pouvoir relancer un isolate Dart dédié en dehors du cycle de vie normal
/// de l'app. Ne fait rien de plus ici : pour un message avec un bloc
/// `notification` (toujours le cas, voir envoyer_notification côté
/// backend), Android affiche déjà la notification système — avec le son du
/// canal indiqué par le backend — sans code Dart.
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
    //    et je crée les canaux AVANT toute notification — sinon la toute
    //    première demande reçue app fermée tomberait sur un canal inexistant
    //    (Android la rangerait alors dans le canal par défaut, sans sonnerie).
    if (!kIsWeb) {
      const parametresAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const parametres = InitializationSettings(android: parametresAndroid);
      await _notificationsLocales.initialize(parametres);
      final android = _notificationsLocales.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_canalNotificationsTaama);
      await android?.createNotificationChannel(_canalDemandesCourse);
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

    // 4. Notifications reçues quand l'app est ouverte au premier plan.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) {
        debugPrint('Notification reçue au premier plan : ${message.notification?.title}');
      }
      if (_estNouvelleDemande(message.data)) {
        // App ouverte : l'écran de demande s'ouvre tout de suite et
        // DemandeEntranteNavigator lance la sonnerie en boucle. Pas de
        // notification système en plus (elle ferait sonner deux fois).
        _traiterDonneesNotification(message.data);
        return;
      }
      _afficherNotificationLocale(message);
      _traiterDonneesNotification(message.data);
    });

    // 4bis. L'utilisateur tape la notification alors que l'app était en
    // arrière-plan (pas tuée) : Firebase relance ce listener au retour au
    // premier plan avec le message qui a été tapé. Le téléphone a déjà sonné
    // (notification système) : on ouvre l'écran sans relancer la sonnerie.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _traiterDonneesNotification(message.data, sonner: false);
    });

    // 4ter. L'app était tuée et a été relancée par un tap sur la
    // notification : le message qui a servi à la relancer est récupéré ici.
    final messageInitial = await _messaging.getInitialMessage();
    if (messageInitial != null) {
      _traiterDonneesNotification(messageInitial.data, sonner: false);
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
      if (kDebugMode) debugPrint('Token FCM mis à jour : $nouveauToken');
      try {
        await ApiService.enregistrerTokenNotification(nouveauToken);
      } catch (e) {
        debugPrint('Erreur ré-enregistrement du token FCM : $e');
      }
    });
  }

  static bool _estNouvelleDemande(Map<String, dynamic> donnees) =>
      donnees['type'] == 'nouvelle_demande';

  /// Ouvre l'écran de demande entrante si ces données FCM correspondent à
  /// une nouvelle demande instantanée assignée — que l'app soit au premier
  /// plan (onMessage), relancée depuis l'arrière-plan (onMessageOpenedApp)
  /// ou depuis un état tué (getInitialMessage). Ignore silencieusement tout
  /// autre type de notification (chat, annulation, etc.).
  static void _traiterDonneesNotification(
    Map<String, dynamic> donnees, {
    bool sonner = true,
  }) {
    if (!_estNouvelleDemande(donnees)) return;
    final demandeId = int.tryParse(donnees['demande_id']?.toString() ?? '');
    if (demandeId == null) return;
    DemandeEntranteNavigator.afficherSiNecessaire(demandeId, sonner: sonner);
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
