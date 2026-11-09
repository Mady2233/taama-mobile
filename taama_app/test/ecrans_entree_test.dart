// Écrans d'entrée (démarrage, présentation, connexion, code) : jamais de
// chiffre inventé, bon positionnement, mise en page qui tient sur un petit
// écran, boutons qui marchent.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_app/screens/connexion_screen.dart';
import 'package:taama_app/screens/onboarding_screen.dart';
import 'package:taama_app/screens/otp_verification_screen.dart';
import 'package:taama_app/services/config_app.dart';
import 'package:taama_app/theme/taama_theme.dart';

Future<void> _ouvrir(WidgetTester t, Widget ecran, {Size taille = const Size(393, 851)}) async {
  await t.binding.setSurfaceSize(taille);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(theme: TaamaTheme.light(), home: ecran));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_vu': true});
    ConfigApp.paiementActif.value = false;
  });

  test('aucun chiffre inventé ni « covoiturage » dans les écrans d’entrée', () {
    for (final fichier in [
      'lib/screens/splash_screen.dart',
      'lib/screens/onboarding_screen.dart',
      'lib/screens/connexion_screen.dart',
      'lib/widgets/taama/marque_taama.dart',
    ]) {
      final source = File(fichier).readAsStringSync();
      for (final interdit in ['500+', '4.8', '100%', 'Covoiturage']) {
        expect(source, isNot(contains(interdit)), reason: '$interdit dans $fichier');
      }
    }
  });

  group('connexion', () {
    testWidgets('positionnement et promesses vraies', (t) async {
      await _ouvrir(t, const EcranConnexion());
      expect(find.text('VTC et moto-taxi à Bamako'), findsOneWidget);
      for (final promesse in ['Prix annoncé avant la course', 'Chauffeurs vérifiés', 'Suivi en direct']) {
        expect(find.text(promesse), findsOneWidget);
      }
    });

    testWidgets('le panneau de connexion est en bas de l’écran, jamais au milieu', (t) async {
      await _ouvrir(t, const EcranConnexion());
      expect(t.getBottomLeft(find.text('Continuer')).dy, greaterThan(851 * 0.75));
    });

    testWidgets('petit écran : rien ne déborde, « Continuer » accessible', (t) async {
      await _ouvrir(t, const EcranConnexion(), taille: const Size(320, 480));
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Continuer'));
      await t.pump();
      await t.tap(find.text('Continuer'));
      await t.pump();
      expect(find.text('Entre ton numéro de téléphone'), findsOneWidget);
    });
  });

  group('code de vérification', () {
    testWidgets('numéro lisible, jamais coupé en fin de ligne', (t) async {
      await _ouvrir(t, const EcranVerificationOTP(numeroTelephone: '76000000'));
      // Espaces insécables : le numéro ne se coupe jamais en fin de ligne.
      expect(find.textContaining(['+223', '76', '00', '00', '00'].join(String.fromCharCode(0xA0))), findsOneWidget);
      expect(find.text('Code de vérification'), findsOneWidget);
    });

    testWidgets('« Modifier le numéro » revient à la connexion', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: TaamaTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EcranVerificationOTP(numeroTelephone: '76000000'))),
            child: const Text('ouvrir'),
          ),
        ),
      ));
      await t.tap(find.text('ouvrir'));
      await t.pumpAndSettle();
      await t.tap(find.text('Modifier le numéro'));
      await t.pumpAndSettle();
      expect(find.text('ouvrir'), findsOneWidget);
    });
  });

  group('présentation', () {
    testWidgets('mode gratuit : jamais la page Mobile Money', (t) async {
      await _ouvrir(t, const EcranOnboarding());
      expect(find.text('Bamako à portée\nde main'), findsOneWidget);
      await t.tap(find.text('Suivant'));
      await t.pumpAndSettle();
      expect(find.text('Voyagez en\ntoute sécurité'), findsOneWidget);
      expect(find.text('Commencer'), findsOneWidget);
      expect(find.textContaining('Mobile Money'), findsNothing);
    });

    testWidgets('petit écran : rien ne déborde', (t) async {
      await _ouvrir(t, const EcranOnboarding(), taille: const Size(320, 480));
      expect(t.takeException(), isNull);
      expect(find.text('Passer'), findsOneWidget);
    });
  });
}
