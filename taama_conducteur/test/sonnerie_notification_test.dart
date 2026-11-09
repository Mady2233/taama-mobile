// Demande reçue téléphone verrouillé : la notification sonne en boucle comme un
// appel, 45 s au plus, remplace celle de FCM, s'ouvre au toucher ; le
// gestionnaire d'arrière-plan ne plante jamais.
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/services/notification_service.dart';
import 'package:taama_conducteur/services/sonnerie_notification.dart';
import 'package:taama_conducteur/services/sonnerie_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sonnerie comme un appel', () {
    final details = SonnerieNotification.details(12);

    test('sonne en boucle jusqu’à la réponse', () {
      expect(details.additionalFlags, contains(SonnerieNotification.flagInsistent));
      expect(SonnerieNotification.flagInsistent, 4, reason: 'Notification.FLAG_INSISTENT');
    });

    test('jamais sans fin : même limite qu’app ouverte', () {
      expect(details.timeoutAfter, SonnerieService.dureeMax.inMilliseconds);
    });

    test('flux sonnerie, priorité maximale, catégorie appel', () {
      expect(details.channelId, SonnerieNotification.idCanal);
      expect(details.audioAttributesUsage, AudioAttributesUsage.notificationRingtone);
      expect(details.importance, Importance.max);
      expect(details.priority, Priority.max);
      expect(details.category, AndroidNotificationCategory.call);
    });

    test('canal neuf (Android fige le son d’un canal existant), même sonnerie Taama', () {
      expect(SonnerieNotification.idCanal, isNot('taama_demandes_course'));
      expect(SonnerieNotification.canal.audioAttributesUsage, AudioAttributesUsage.notificationRingtone);
      expect((SonnerieNotification.canal.sound as RawResourceAndroidNotificationSound).sound, 'sonnerie_course');
      expect(File('android/app/src/main/res/raw/sonnerie_course.wav').existsSync(), isTrue);
    });

    test('remplace la notification de FCM : même tag que le serveur', () {
      // trajets/notifications.py : notification['tag'] = f'demande_{demande_id}'
      expect(details.tag, 'demande_12');
    });
  });

  group('toucher la notification', () {
    test('ouvre la bonne demande', () {
      expect(SonnerieNotification.demandeDepuisPayload(SonnerieNotification.payload(42)), 42);
    });

    test('toute autre notification est ignorée', () {
      for (final payload in [null, '', 'chat:42', 'nouvelle_demande:', 'nouvelle_demande:abc']) {
        expect(SonnerieNotification.demandeDepuisPayload(payload), isNull, reason: '$payload');
      }
    });
  });

  group('gestionnaire d’arrière-plan', () {
    test('autres messages : rien, sans erreur', () async {
      await gestionnaireMessageArrierePlan(const RemoteMessage(data: {'type': 'nouveau_message'}));
      await gestionnaireMessageArrierePlan(const RemoteMessage(data: {'type': 'nouvelle_demande'}));
    });

    test('notifications indisponibles : jamais de plantage (celle de FCM reste)', () async {
      await gestionnaireMessageArrierePlan(
          const RemoteMessage(data: {'type': 'nouvelle_demande', 'demande_id': '12'}));
      await gestionnaireMessageArrierePlan(
          const RemoteMessage(data: {'type': 'demande_annulee', 'demande_id': '12'}));
    });

    test('arrêter une sonnerie absente : sans erreur', () async {
      await SonnerieNotification.arreter(12);
    });
  });
}
