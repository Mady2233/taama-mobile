// Relances de l'enregistrement du jeton de notification : jeton redemandé
// à Firebase s'il est nul, retour au premier plan seulement après un échec,
// au plus toutes les 2 min.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_app/services/api_service.dart';
import 'package:taama_app/services/enregistrement_jeton.dart';
import 'package:taama_app/services/notification_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.definirToken('session-essai');
    EnregistrementJeton.reinitialiser();
    NotificationService.reinitialiserJeton();
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.chargerTokenPersiste();
    EnregistrementJeton.reinitialiser();
    NotificationService.reinitialiserJeton();
  });

  /// Corps des requêtes reçues par le serveur (toujours 200).
  Future<List<String>> serveur(Future<void> Function() corps) async {
    final recus = <String>[];
    await http.runWithClient(corps, () => MockClient((requete) async {
          recus.add(requete.body);
          return http.Response('{}', 200);
        }));
    return recus;
  }

  test('jeton encore nul : redemandé à Firebase, puis enregistré', () async {
    NotificationService.demanderJeton = () async => 'jeton-firebase';
    final recus = await serveur(NotificationService.reenregistrerJeton);
    expect(recus.single, contains('jeton-firebase'));
    expect(NotificationService.token, 'jeton-firebase');
  });

  test('Firebase muet : rien n’est envoyé, sans erreur', () async {
    NotificationService.demanderJeton = () async => throw Exception('Firebase indisponible');
    expect(await serveur(NotificationService.reenregistrerJeton), isEmpty);
  });

  test('jeton connu : Firebase n’est pas redemandé', () async {
    var demandes = 0;
    NotificationService.token = 'jeton-connu';
    NotificationService.demanderJeton = () async {
      demandes++;
      return 'autre';
    };
    final recus = await serveur(NotificationService.reenregistrerJeton);
    expect(recus.single, contains('jeton-connu'));
    expect(demandes, 0);
  });

  test('sans session : ni Firebase ni requête', () async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.chargerTokenPersiste();
    var demandes = 0;
    NotificationService.demanderJeton = () async {
      demandes++;
      return 'jeton';
    };
    expect(await serveur(NotificationService.reenregistrerJeton), isEmpty);
    expect(demandes, 0);
  });

  test('retour au premier plan : rien si le dernier enregistrement a réussi', () async {
    NotificationService.token = 'jeton-connu';
    await serveur(() => EnregistrementJeton.enregistrer('jeton-connu'));
    expect(EnregistrementJeton.derniereIssue, IssueJeton.enregistre);
    expect(await serveur(NotificationService.reenregistrerSiEchec), isEmpty);
  });

  test('retour après un abandon (réseau) : nouvel essai, au plus toutes les 2 min', () async {
    NotificationService.token = 'jeton-connu';
    EnregistrementJeton.derniereIssue = IssueJeton.abandonne;
    final debut = DateTime(2026, 11, 11, 10);
    expect((await serveur(() => NotificationService.reenregistrerSiEchec(maintenant: debut))).length, 1);
    EnregistrementJeton.derniereIssue = IssueJeton.abandonne;
    expect(await serveur(() => NotificationService.reenregistrerSiEchec(
        maintenant: debut.add(const Duration(minutes: 1)))), isEmpty);
    expect((await serveur(() => NotificationService.reenregistrerSiEchec(
        maintenant: debut.add(const Duration(minutes: 3))))).length, 1);
  });

  test('retour après un refus définitif ou une mise à jour requise : rien', () async {
    NotificationService.token = 'jeton-connu';
    for (final issue in [IssueJeton.refuse, IssueJeton.miseAJourRequise]) {
      EnregistrementJeton.derniereIssue = issue;
      expect(await serveur(NotificationService.reenregistrerSiEchec), isEmpty, reason: '$issue');
    }
  });
}
