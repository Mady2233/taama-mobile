import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/main.dart';
import 'package:taama_conducteur/screens/connexion_screen.dart';
import 'package:taama_conducteur/screens/onboarding_screen.dart';
import 'package:taama_conducteur/screens/splash_screen.dart';
import 'package:taama_conducteur/services/demande_entrante_navigator.dart';

/// Démarrage sans session : splash, puis onboarding au premier lancement,
/// connexion ensuite. Aucun appel réseau (préférences simulées).
Future<void> _demarrer(WidgetTester tester) async {
  await tester.pumpWidget(const TaamaConducApp());
  expect(find.byType(EcranSplash), findsOneWidget);
  await tester.pump(const Duration(seconds: 3)); // animations du splash (2,6 s)
  await tester.pump(const Duration(milliseconds: 700)); // transition en fondu
}

void main() {
  // Le démarrage lit le numéro de build (mise à jour obligatoire) : sans canal
  // natif en test, valeur simulée.
  setUp(() => PackageInfo.setMockInitialValues(
        appName: 'Taama Conducteur',
        packageName: 'com.taama.taama_conducteur',
        version: '1.0.0',
        buildNumber: '61',
        buildSignature: '',
      ));

  testWidgets('premier lancement : splash puis onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _demarrer(tester);
    expect(find.byType(EcranOnboarding), findsOneWidget);
  });

  testWidgets('lancement suivant : splash puis connexion', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_vu': true});
    await _demarrer(tester);
    expect(find.byType(EcranConnexion), findsOneWidget);
  });

  // App ouverte depuis la notification d'une demande : la demande est poussée
  // pendant le démarrage (DemandeEntranteNavigator) et doit y rester.
  testWidgets('demande ouverte pendant le démarrage : elle reste à l’écran', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_vu': true});
    await tester.pumpWidget(const TaamaConducApp());
    await tester.pump();
    unawaited(navigatorKey.currentState!
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('demande')))));
    await tester.pump(const Duration(seconds: 3)); // animations du splash (2,6 s)
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('demande'), findsOneWidget);
    // Dessous : la connexion ; le démarrage a quitté la pile.
    expect(find.byType(EcranConnexion, skipOffstage: false), findsOneWidget);
    expect(find.byType(EcranSplash, skipOffstage: false), findsNothing);
  });
}
