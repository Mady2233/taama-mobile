// Suivi de position du chauffeur : service au premier plan dès qu'il est en
// ligne, une seule configuration (geolocator n'ouvre qu'un flux GPS par app),
// jamais de position périmée, polling suspendu hors de l'écran.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/services/location_service.dart';
import 'package:taama_conducteur/services/polling_premier_plan.dart';

bool _envoyer({
  int age = 0,
  int? depuis = 20,
  double? metres = 0,
  double metresMin = 25,
}) =>
    LocationService.doitEnvoyerPosition(
      ageMesure: Duration(seconds: age),
      depuisDernierEnvoi: depuis == null ? null : Duration(seconds: depuis),
      metresParcourus: metres,
      metresMin: metresMin,
    );

String _lire(String chemin) => File(chemin).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('doitEnvoyerPosition', () {
    test('premier envoi : oui', () {
      expect(_envoyer(depuis: null, metres: null), isTrue);
    });
    test('immobile : un envoi toutes les 15 s, pas plus', () {
      expect(_envoyer(depuis: 14), isFalse);
      expect(_envoyer(depuis: 15), isTrue);
    });
    test('déplacement de 25 m : tout de suite, mais au plus un envoi par 4 s', () {
      expect(_envoyer(depuis: 5, metres: 24.9), isFalse);
      expect(_envoyer(depuis: 5, metres: 25), isTrue);
      expect(_envoyer(depuis: 3, metres: 500), isFalse);
    });
    test('mesure de plus de 30 s : plus rien, même après 15 s ou un grand écart', () {
      expect(_envoyer(age: 30, depuis: 60), isTrue);
      expect(_envoyer(age: 31, depuis: 60), isFalse);
      expect(_envoyer(age: 31, depuis: null, metres: null), isFalse);
      expect(_envoyer(age: 31, depuis: 60, metres: 5000), isFalse);
    });
    test('seuil de déplacement propre au canal de course', () {
      expect(_envoyer(depuis: 5, metres: 10, metresMin: 10), isTrue);
      expect(_envoyer(depuis: 5, metres: 9, metresMin: 10), isFalse);
    });
  });

  group('réglages Android', () {
    final json = LocationService.parametresPositionAndroid().toJson();
    final notification = json['foregroundNotificationConfig'] as Map<String, dynamic>;

    test('une vraie mesure toutes les 5 s, même à l’arrêt', () {
      expect(json['distanceFilter'], 0);
      expect(json['timeInterval'], 5000);
    });

    test('service au premier plan, notification non balayable', () {
      expect(notification['notificationTitle'], isNotEmpty);
      expect(notification['setOngoing'], isTrue);
      expect(notification['enableWakeLock'], isTrue);
    });

    test('icône conservée en release : référencée par l’icône de l’app', () {
      final icone = notification['notificationIcon'] as Map<String, dynamic>;
      expect(icone['defType'], 'drawable');
      expect(icone['name'], 'ic_launcher_foreground');
      expect(File('android/app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png').existsSync(), isTrue);
      expect(
        _lire('android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml'),
        contains('@drawable/ic_launcher_foreground'),
      );
    });

    test('une seule configuration dans toute l’app', () {
      final fichiers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      final avecService = fichiers
          .where((f) => f.readAsStringSync().contains('ForegroundNotificationConfig('))
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(avecService, ['location_service.dart']);
      expect(_lire('lib/screens/navigation_screen.dart'), contains('LocationService.parametresPositionAndroid()'));
    });

    test('jamais « Toujours » : autorisation « pendant l’utilisation » seulement', () {
      expect(_lire('android/app/src/main/AndroidManifest.xml'), isNot(contains('android.permission.ACCESS_BACKGROUND_LOCATION"')));
      expect(_lire('lib/services/location_service.dart'), isNot(contains('LocationPermission.always')));
    });
  });

  group('appVisible', () {
    final binding = TestWidgetsFlutterBinding.instance;
    tearDown(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

    test('à l’écran : oui ; en arrière-plan : non', () {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(appVisible(), isTrue);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(appVisible(), isTrue);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      expect(appVisible(), isFalse);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(appVisible(), isFalse);
    });
  });

  group('PollingPremierPlan', () {
    PollingPremierPlan polling(void Function() appel) => PollingPremierPlan(
          intervalle: const Duration(seconds: 5),
          action: () async => appel(),
        );

    testWidgets('tourne à l’écran, s’arrête en arrière-plan', (t) async {
      var appels = 0;
      final p = polling(() => appels++)..demarrer();
      await t.pump(const Duration(seconds: 11));
      expect(appels, 2);

      p.suspendre();
      await t.pump(const Duration(minutes: 5));
      expect(appels, 2);
    });

    testWidgets('au retour : action immédiate, puis reprise', (t) async {
      var appels = 0;
      final p = polling(() => appels++)..demarrer();
      p.suspendre();

      p.reprendre();
      expect(appels, 1);
      await t.pump(const Duration(seconds: 6));
      expect(appels, 2);
      p.suspendre();
    });

    testWidgets('deux reprises : jamais deux minuteries', (t) async {
      var appels = 0;
      final p = polling(() => appels++)..demarrer();
      p.suspendre();
      p.reprendre();
      p.reprendre();
      expect(appels, 1);
      await t.pump(const Duration(seconds: 6));
      expect(appels, 2);
      p.suspendre();
    });
  });

  test('l’accueil demande l’explication avant tout passage en ligne', () {
    final source = _lire('lib/screens/espace_chauffeur_screen.dart');
    final bascule = source.substring(source.indexOf('Future<void> _basculerDisponibilite'));
    expect(
      bascule.indexOf('_explicationPositionVue'),
      lessThan(bascule.indexOf('ApiService.changerDisponibilite')),
    );
    expect(source, isNot(contains('_serviceLocalisationGenerale.demarrerSuiviPositionEnLigne();\n      }\n    } on ApiException')));
  });
}
