// Fin de session (FinDeSession, ClientSession) : un 401 reçu pour la session
// ouverte l'efface et ramène à l'écran de connexion, avec un message, une seule
// fois. Jamais pour une autre session (reprise d'une déconnexion différée), ni
// pour la déconnexion ou la suppression du compte, ni sur les autres codes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/config/api_config.dart';
import 'package:taama_conducteur/screens/connexion_screen.dart';
import 'package:taama_conducteur/services/api_service.dart';
import 'package:taama_conducteur/services/deconnexion.dart';
import 'package:taama_conducteur/services/fin_de_session.dart';
import 'package:taama_conducteur/services/demande_entrante_navigator.dart';
import 'package:taama_conducteur/services/notification_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.definirToken('session-a');
    NotificationService.reinitialiserJeton();
    Deconnexion.reinitialiser();
    Deconnexion.supprimerJetonFirebase = () async {};
    FinDeSession.reinitialiser();
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.chargerTokenPersiste();
    NotificationService.reinitialiserJeton();
    Deconnexion.reinitialiser();
    FinDeSession.reinitialiser();
  });

  /// Une requête vers [chemin] de l'API (ou l'adresse complète [adresse]),
  /// avec le jeton de session [jeton], à laquelle le serveur répond [code], à
  /// travers ClientSession.
  Future<void> appeler(String chemin, {String? jeton, required int code, String? adresse}) =>
      http.runWithClient(
        () => http.get(
          Uri.parse(adresse ?? '${ApiConfig.baseUrl}$chemin'),
          headers: {if (jeton != null) 'Authorization': 'Token $jeton'},
        ),
        () => ClientSession(MockClient((_) async => http.Response('{}', code))),
      );

  late _Navigations navigations;

  Future<void> ecran(WidgetTester t) {
    navigations = _Navigations();
    return t.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [navigations],
      home: const Scaffold(body: Text('accueil')),
    ));
  }

  Future<void> laisser(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('401 de la session ouverte : session effacée, écran de connexion, message', (t) async {
    await ecran(t);
    await appeler('/trajets/demandes/mes-demandes/', jeton: 'session-a', code: 401);
    await laisser(t);
    expect(ApiService.estConnecte, isFalse);
    expect(find.byType(EcranConnexion), findsOneWidget);
    expect(find.text(messageSessionFermee), findsOneWidget);
    expect(FinDeSession.enCours, isFalse);
  });

  testWidgets('deux 401 simultanés : une seule fin de session', (t) async {
    await ecran(t);
    // Comme le polling, qui envoie ses requêtes en parallèle : les deux 401
    // arrivent avant que la session soit effacée.
    await Future.wait([
      appeler('/trajets/demandes/mes-demandes/', jeton: 'session-a', code: 401),
      appeler('/trajets/courier/mes-livraisons/', jeton: 'session-a', code: 401),
    ]);
    await laisser(t);
    expect(navigations.ouvertures, 2); // l'accueil, puis une seule connexion
    expect(find.byType(EcranConnexion), findsOneWidget);
    expect(find.text(messageSessionFermee), findsOneWidget);
  });

  testWidgets('un message d’écran déjà affiché : celui de la fin de session une seule fois', (t) async {
    await ecran(t);
    ScaffoldMessenger.of(navigatorKey.currentContext!)
        .showSnackBar(const SnackBar(content: Text(messageSessionFermee)));
    await t.pump();
    await appeler('/trajets/demandes/mes-demandes/', jeton: 'session-a', code: 401);
    await laisser(t);
    expect(find.text(messageSessionFermee), findsOneWidget);
    // Un deuxième message en file s'afficherait après le premier (4 s).
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 1));
    expect(find.text(messageSessionFermee), findsNothing);
  });

  testWidgets('pendant une opération de compte : un 401 d’une autre requête ne ferme rien', (t) async {
    await ecran(t);
    await FinDeSession.pendant(
      () => appeler('/trajets/demandes/mes-demandes/', jeton: 'session-a', code: 401),
    );
    await laisser(t);
    expect(ApiService.token, 'session-a');
    expect(find.text('accueil'), findsOneWidget);
    // Retenu pour l'écran : la session est fermée côté serveur.
    expect(FinDeSession.fermeeDuranteOperation, isTrue);
    // Oublié à la prochaine opération ; un 401 d'un autre jeton n'y compte pas.
    await FinDeSession.pendant(
      () => appeler('/trajets/demandes/mes-demandes/', jeton: 'ancienne-session', code: 401),
    );
    expect(FinDeSession.fermeeDuranteOperation, isFalse);
    // L'opération finie, un 401 ferme la session de nouveau.
    await appeler('/trajets/demandes/mes-demandes/', jeton: 'session-a', code: 401);
    await laisser(t);
    expect(find.byType(EcranConnexion), findsOneWidget);
  });

  testWidgets('écran « Mise à jour requise » affiché : session effacée, l’écran reste', (t) async {
    FinDeSession.ecranBloquantAffiche = () => true;
    await ecran(t);
    await appeler('/trajets/demandes/mes-demandes/', jeton: 'session-a', code: 401);
    await laisser(t);
    expect(ApiService.estConnecte, isFalse);
    expect(find.text('accueil'), findsOneWidget);
    expect(find.byType(EcranConnexion), findsNothing);
  });

  testWidgets('401 d’un autre jeton (reprise d’une déconnexion différée) : rien', (t) async {
    await ecran(t);
    await appeler('/trajets/notifications/retirer-token/', jeton: 'ancienne-session', code: 401);
    await laisser(t);
    expect(ApiService.token, 'session-a');
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('401 de la déconnexion ou de la suppression du compte : l’écran s’en charge', (t) async {
    await ecran(t);
    await appeler('/comptes/deconnexion/', jeton: 'session-a', code: 401);
    await appeler('/comptes/supprimer-mon-compte/', jeton: 'session-a', code: 401);
    await laisser(t);
    expect(ApiService.token, 'session-a');
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('401 d’un autre hôte (itinéraires, tuiles, stockage) : jamais de fin de session', (t) async {
    await ecran(t);
    for (final adresse in [
      'https://router.project-osrm.org/route/v1/driving/-8.0,12.6;-8.1,12.7',
      'https://api.maptiler.com/maps/dataviz/256/15/1/1@2x.png',
      'https://pub-exemple.r2.dev/profils/photo.jpg',
      // Même hôte, autre schéma : une autre origine.
      '${ApiConfig.baseUrl.replaceFirst('https://', 'http://')}/trajets/demandes/mes-demandes/',
    ]) {
      await appeler('', adresse: adresse, jeton: 'session-a', code: 401);
    }
    await laisser(t);
    expect(ApiService.token, 'session-a');
    expect(find.text('accueil'), findsOneWidget);
  });

  testWidgets('autres codes, ou requête sans session : rien', (t) async {
    await ecran(t);
    for (final code in [200, 403, 409, 500]) {
      await appeler('/trajets/demandes/mes-demandes/', jeton: 'session-a', code: code);
    }
    await appeler('/comptes/verifier-otp/', code: 401);
    await laisser(t);
    expect(ApiService.token, 'session-a');
    expect(find.text('accueil'), findsOneWidget);
  });
}

/// Compte les écrans ouverts : une seule connexion, jamais deux.
class _Navigations extends NavigatorObserver {
  int ouvertures = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => ouvertures++;
}
