// Déconnexion : 200 ou 401 déconnecté, 409 ou course connue refusé ; sinon
// session effacée quand même, et au lancement suivant seul le jeton de
// notification de cet appareil est retiré du serveur, avec l'ancien jeton de
// session : jamais de session révoquée (constat #0). Jeton Firebase supprimé
// (retenté s'il échoue) et NotificationService.token remis à nul.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_app/services/api_service.dart';
import 'package:taama_app/services/deconnexion.dart';
import 'package:taama_app/services/notification_service.dart';
import 'package:taama_app/services/version_app.dart';

const _deconnexion = '/comptes/deconnexion/';
const _retrait = '/trajets/notifications/retirer-token/';
const _appareilA = AppareilARetirer(session: 'session-a', notification: 'jeton-firebase');

void main() {
  late int suppressionsFirebase;
  late bool firebaseEnEchec;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.definirToken('session-a');
    NotificationService.reinitialiserJeton();
    NotificationService.token = 'jeton-firebase';
    Deconnexion.reinitialiser();
    VersionApp.surMiseAJourRequise = null;
    suppressionsFirebase = 0;
    firebaseEnEchec = false;
    Deconnexion.supprimerJetonFirebase = () async {
      suppressionsFirebase++;
      if (firebaseEnEchec) throw Exception('Firebase injoignable');
    };
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.chargerTokenPersiste();
    NotificationService.reinitialiserJeton();
    Deconnexion.reinitialiser();
  });

  /// Requêtes reçues, « chemin Authorization jeton-du-corps » ; [code] :
  /// réponse du serveur (null : réseau coupé).
  Future<List<String>> serveur(Future<void> Function() corps, {int? Function()? code}) async {
    final recues = <String>[];
    await http.runWithClient(() async {
      await corps();
      await Deconnexion.tachesTerminees;
    }, () => MockClient((requete) async {
          final chemin = requete.url.path.replaceFirst(RegExp(r'^.*/api'), '');
          final jeton = requete.body.isEmpty ? '' : ' ${(jsonDecode(requete.body) as Map)['token']}';
          recues.add('$chemin ${requete.headers['Authorization'] ?? '-'}$jeton');
          final reponse = code == null ? 200 : code();
          if (reponse == null) throw http.ClientException('Réseau coupé');
          return http.Response('{}', reponse);
        }));
    return recues;
  }

  Future<SharedPreferences> preferences() => SharedPreferences.getInstance();

  Future<List<AppareilARetirer>> enAttente() => Deconnexion.appareilsEnAttente();

  Future<bool> firebaseASupprimer() async =>
      (await preferences()).getBool(Deconnexion.cleJetonFirebaseASupprimer) ?? false;

  /// Lancement suivant une déconnexion hors ligne : plus de session, les
  /// retraits [appareils] en attente.
  Future<void> deconnecteAvecEnAttente(List<AppareilARetirer> appareils) async {
    SharedPreferences.setMockInitialValues({
      Deconnexion.cleAppareilsARetirer: [for (final a in appareils) a.enTexte()],
    });
    await ApiService.chargerTokenPersiste();
  }

  test('200 : déconnecté, session et jeton de notification effacés, rien en attente', () async {
    late IssueDeconnexion issue;
    final recues = await serveur(() async => issue = await Deconnexion.seDeconnecter());
    expect(issue, IssueDeconnexion.deconnecte);
    expect(recues, ['$_deconnexion Token session-a']);
    expect(ApiService.estConnecte, isFalse);
    expect((await preferences()).getString('auth_token'), isNull);
    expect(NotificationService.token, isNull);
    expect(await enAttente(), isEmpty);
    expect(suppressionsFirebase, 1);
    expect(await firebaseASupprimer(), isFalse);
  });

  test('issue : seule « course en cours » laisse la session', () {
    expect(IssueDeconnexion.deconnecte.estDeconnecte, isTrue);
    expect(IssueDeconnexion.deconnecteHorsReseau.estDeconnecte, isTrue);
    expect(IssueDeconnexion.courseEnCours.estDeconnecte, isFalse);
  });

  test('401 (session déjà révoquée) : déconnecté, rien en attente', () async {
    late IssueDeconnexion issue;
    await serveur(() async => issue = await Deconnexion.seDeconnecter(), code: () => 401);
    expect(issue, IssueDeconnexion.deconnecte);
    expect(ApiService.estConnecte, isFalse);
    expect(await enAttente(), isEmpty);
  });

  test('409 : refusé, rien n’est effacé, Firebase intact', () async {
    late IssueDeconnexion issue;
    await serveur(() async => issue = await Deconnexion.seDeconnecter(), code: () => 409);
    expect(issue, IssueDeconnexion.courseEnCours);
    expect(ApiService.token, 'session-a');
    expect((await preferences()).getString('auth_token'), 'session-a');
    expect(NotificationService.token, 'jeton-firebase');
    expect(suppressionsFirebase, 0);
    expect(await enAttente(), isEmpty);
  });

  test('course en cours connue de l’app : refusé sans requête', () async {
    late IssueDeconnexion issue;
    final recues = await serveur(
        () async => issue = await Deconnexion.seDeconnecter(courseEnCoursLocale: true));
    expect(issue, IssueDeconnexion.courseEnCours);
    expect(recues, isEmpty);
    expect(ApiService.token, 'session-a');
    expect(suppressionsFirebase, 0);
  });

  test('réseau, délai dépassé, 5xx, 426, 429 : session effacée, retrait de l’appareil à faire', () async {
    final issues = <String, int? Function()>{
      'réseau coupé': () => null,
      'délai dépassé': () => throw TimeoutException('délai'),
      '500': () => 500,
      '503': () => 503,
      '426': () => 426,
      '429': () => 429,
    };
    for (final MapEntry(key: nom, value: code) in issues.entries) {
      SharedPreferences.setMockInitialValues({});
      await ApiService.definirToken('session-a');
      NotificationService.token = 'jeton-firebase';
      late IssueDeconnexion issue;
      await serveur(() async => issue = await Deconnexion.seDeconnecter(), code: code);
      expect(issue, IssueDeconnexion.deconnecteHorsReseau, reason: nom);
      expect(issue.estDeconnecte, isTrue, reason: nom);
      expect(ApiService.estConnecte, isFalse, reason: nom);
      expect((await preferences()).getString('auth_token'), isNull, reason: nom);
      expect(NotificationService.token, isNull, reason: nom);
      // Seulement l'ancien jeton de session et le jeton de notification.
      expect(await enAttente(), [_appareilA], reason: nom);
    }
  });

  test('sans jeton de notification connu : rien à retirer du serveur', () async {
    NotificationService.token = null;
    await serveur(Deconnexion.seDeconnecter, code: () => 503);
    expect(ApiService.estConnecte, isFalse);
    expect(await enAttente(), isEmpty);
    expect(await firebaseASupprimer(), isFalse); // supprimé tout de suite
  });

  test('l’ancien jeton ne sert qu’au retrait : les autres requêtes partent sans session', () async {
    await serveur(Deconnexion.seDeconnecter, code: () => 503);
    final recues = await serveur(() => ApiService.enregistrerTokenNotification('jeton-x'));
    expect(recues.single, contains(' - '));
  });

  test('constat #0 : hors ligne, reconnexion ailleurs, rejeu : aucune session révoquée', () async {
    // Déconnexion hors ligne sur ce téléphone.
    await serveur(Deconnexion.seDeconnecter, code: () => null);
    // Reconnexion ailleurs (autre téléphone ou autre app) avec le même jeton :
    // invisible ici. Au lancement suivant, le rejeu ne touche qu'à cet appareil.
    final recues = await serveur(Deconnexion.reprendre);
    expect(recues, ['$_retrait Token session-a jeton-firebase']);
    expect(recues.where((r) => r.startsWith(_deconnexion)), isEmpty);
    expect(await enAttente(), isEmpty);
  });

  test('reprise : trace effacée sur 200, 400 ou 401', () async {
    for (final reponse in [200, 400, 401]) {
      await deconnecteAvecEnAttente([_appareilA]);
      final recues = await serveur(Deconnexion.reprendre, code: () => reponse);
      expect(recues, ['$_retrait Token session-a jeton-firebase'], reason: '$reponse');
      expect(await enAttente(), isEmpty, reason: '$reponse');
    }
  });

  test('reprise : réseau, 5xx ou 404, la trace reste pour le lancement suivant', () async {
    for (final code in <int? Function()>[() => null, () => 500, () => 404]) {
      await deconnecteAvecEnAttente([_appareilA]);
      await serveur(Deconnexion.reprendre, code: code);
      expect(await enAttente(), [_appareilA]);
    }
  });

  test('reprise pendant une autre session : la sienne n’est ni utilisée ni coupée', () async {
    await deconnecteAvecEnAttente([_appareilA]);
    await ApiService.definirToken('session-b');
    final recues = await serveur(Deconnexion.reprendre);
    expect(recues, ['$_retrait Token session-a jeton-firebase']);
    expect(ApiService.token, 'session-b');
    expect(await enAttente(), isEmpty);
  });

  test('reprise : même jeton que la session ouverte, abandonnée sans requête', () async {
    await deconnecteAvecEnAttente([_appareilA]);
    await ApiService.definirToken('session-a');
    expect(await serveur(Deconnexion.reprendre), isEmpty);
    expect(await enAttente(), isEmpty);
  });

  test('deux retraits en attente (deux comptes) : les deux sont repris', () async {
    const appareilB = AppareilARetirer(session: 'session-b', notification: 'jeton-firebase-2');
    await deconnecteAvecEnAttente([_appareilA, appareilB]);
    final recues = await serveur(Deconnexion.reprendre);
    expect(recues, ['$_retrait Token session-a jeton-firebase', '$_retrait Token session-b jeton-firebase-2']);
    expect(await enAttente(), isEmpty);
  });

  test('trace illisible : ignorée, sans erreur', () async {
    SharedPreferences.setMockInitialValues({
      Deconnexion.cleAppareilsARetirer: ['pas du json', '{"session": ""}', _appareilA.enTexte()],
    });
    await ApiService.chargerTokenPersiste();
    expect(await serveur(Deconnexion.reprendre), ['$_retrait Token session-a jeton-firebase']);
  });

  test('connexion avec le même jeton : le retrait en attente est abandonné', () async {
    firebaseEnEchec = true;
    await serveur(Deconnexion.seDeconnecter, code: () => 503);
    expect(await firebaseASupprimer(), isTrue);
    await ApiService.definirToken('session-a'); // le serveur rend le même jeton
    await Deconnexion.apresConnexion();
    expect(await enAttente(), isEmpty);
    expect(await firebaseASupprimer(), isFalse); // le jeton sert à la session
  });

  test('connexion avec un autre jeton : le retrait en attente reste à faire', () async {
    firebaseEnEchec = true;
    await serveur(Deconnexion.seDeconnecter, code: () => 503);
    await ApiService.definirToken('session-b');
    await Deconnexion.apresConnexion();
    expect(await enAttente(), [_appareilA]);
    expect(await firebaseASupprimer(), isFalse); // le jeton sert à la nouvelle session
  });

  test('une connexion attend la fin de la reprise en cours', () async {
    await deconnecteAvecEnAttente([_appareilA]);
    final reponse = Completer<http.Response>();
    var seconde = false;
    await http.runWithClient(() async {
      final premiere = Deconnexion.reprendre();
      final attente = Deconnexion.reprendre().then((_) => seconde = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seconde, isFalse);
      reponse.complete(http.Response('{}', 200));
      await premiere;
      await attente;
    }, () => MockClient((_) => reponse.future));
    expect(seconde, isTrue);
    expect(await enAttente(), isEmpty);
  });

  test('deleteToken en échec : jeton noté, supprimé au lancement suivant', () async {
    firebaseEnEchec = true;
    await serveur(Deconnexion.seDeconnecter);
    expect(suppressionsFirebase, 1);
    expect(await firebaseASupprimer(), isTrue);
    expect(NotificationService.token, isNull);

    firebaseEnEchec = false;
    NotificationService.token = 'jeton-firebase'; // relu par Firebase au lancement
    await serveur(Deconnexion.reprendre);
    expect(suppressionsFirebase, 2);
    expect(await firebaseASupprimer(), isFalse);
    expect(NotificationService.token, isNull);
  });

  test('deleteToken sans réponse : délai maximal, puis noté pour le lancement suivant', () async {
    Deconnexion.delaiFirebase = const Duration(milliseconds: 30);
    Deconnexion.supprimerJetonFirebase = () => Completer<void>().future;
    await serveur(Deconnexion.seDeconnecter);
    expect(ApiService.estConnecte, isFalse);
    expect(await firebaseASupprimer(), isTrue);
  });

  test('jeton Firebase noté mais session rouverte : jamais supprimé', () async {
    SharedPreferences.setMockInitialValues({
      'auth_token': 'session-b',
      Deconnexion.cleJetonFirebaseASupprimer: true,
    });
    await ApiService.chargerTokenPersiste();
    await serveur(Deconnexion.reprendre);
    expect(suppressionsFirebase, 0);
    expect(await firebaseASupprimer(), isFalse);
  });

  test('reprise : sans version annoncée, et un 426 n’ouvre pas « Mise à jour requise »', () async {
    VersionApp.annoncer(app: 'essai', plateforme: 'android', build: 1);
    final refus = VersionApp.refusRecus;
    final entetes = <String, Map<String, String>>{};
    await deconnecteAvecEnAttente([_appareilA]);
    await http.runWithClient(() async {
      await Deconnexion.reprendre();
      await ApiService.definirToken('session-b');
      await Deconnexion.seDeconnecter();
      await Deconnexion.tachesTerminees;
    }, () => MockClient((requete) async {
          entetes[requete.url.path.replaceFirst(RegExp(r'^.*/api'), '')] = requete.headers;
          return http.Response('{"code": "MISE_A_JOUR_REQUISE"}', 426);
        }));
    VersionApp.oublier();
    expect(entetes[_retrait]!['Authorization'], 'Token session-a');
    expect(entetes[_retrait]!.containsKey('X-Taama-App'), isFalse); // reprise
    expect(entetes[_deconnexion]!['Authorization'], 'Token session-b');
    expect(entetes[_deconnexion]!.containsKey('X-Taama-App'), isTrue); // demandée par l'utilisateur
    expect(VersionApp.refusRecus, refus + 1); // seulement la déconnexion demandée
  });

  testWidgets('serveur muet : 12 s au plus, puis session effacée et retrait à faire', (t) async {
    await http.runWithClient(() async {
      IssueDeconnexion? issue;
      unawaited(Deconnexion.seDeconnecter().then((i) => issue = i));
      await t.pump(const Duration(seconds: 11));
      expect(issue, isNull);
      expect(ApiService.estConnecte, isTrue);
      await t.pump(const Duration(seconds: 2));
      expect(issue, IssueDeconnexion.deconnecteHorsReseau);
    }, () => MockClient((_) => Completer<http.Response>().future));
    expect(ApiService.estConnecte, isFalse);
    expect(await enAttente(), [_appareilA]);
  });

  testWidgets('reprise, serveur muet : 12 s au plus, la trace reste', (t) async {
    await deconnecteAvecEnAttente([_appareilA]);
    await http.runWithClient(() async {
      var finie = false;
      unawaited(Deconnexion.reprendre().then((_) => finie = true));
      await t.pump(const Duration(seconds: 11));
      expect(finie, isFalse);
      await t.pump(const Duration(seconds: 2));
      expect(finie, isTrue);
    }, () => MockClient((_) => Completer<http.Response>().future));
    expect(await enAttente(), [_appareilA]);
  });

  test('deleteToken trop lent puis abouti après une connexion : le jeton est redemandé', () async {
    final natif = Completer<void>();
    var appels = 0;
    Deconnexion.delaiFirebase = const Duration(milliseconds: 30);
    Deconnexion.supprimerJetonFirebase = () {
      appels++;
      return natif.future;
    };
    await serveur(Deconnexion.seDeconnecter);
    expect(await firebaseASupprimer(), isTrue);

    // Connexion pendant que la suppression native est encore en route.
    await serveur(Deconnexion.reprendre);
    expect(appels, 1); // jamais un deuxième appel
    await ApiService.definirToken('session-b');
    NotificationService.token = 'jeton-mort';
    NotificationService.demanderJeton = () async => 'jeton-neuf';
    final recues = <String>[];
    await http.runWithClient(() async {
      await Deconnexion.apresConnexion();
      natif.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }, () => MockClient((requete) async {
          recues.add(requete.body);
          return http.Response('{}', 200);
        }));
    expect(NotificationService.token, 'jeton-neuf');
    expect(recues.single, contains('jeton-neuf'));
  });

  test('deleteToken abouti après le délai, avant toute connexion : marque effacée, aucun deuxième appel', () async {
    final natif = Completer<void>();
    var appels = 0;
    Deconnexion.delaiFirebase = const Duration(milliseconds: 30);
    Deconnexion.supprimerJetonFirebase = () {
      appels++;
      return natif.future;
    };
    await serveur(Deconnexion.seDeconnecter);
    expect(await firebaseASupprimer(), isTrue);
    NotificationService.token = 'jeton-recharge';
    natif.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await firebaseASupprimer(), isFalse);
    expect(NotificationService.token, isNull);
    await serveur(Deconnexion.reprendre);
    expect(appels, 1);
  });

  test('session vide : déconnecté, aucune session envoyée', () async {
    await ApiService.definirToken('');
    expect(ApiService.estConnecte, isFalse);
    expect(ApiService.token, isNull);
  });
}
