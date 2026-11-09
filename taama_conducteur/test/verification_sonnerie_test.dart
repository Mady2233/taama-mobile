// « Mon téléphone sonnera-t-il ? » : seuls les problèmes réellement lus sont
// signalés, chacun avec un bouton « Régler » qui ouvre le bon réglage.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/services/verification_sonnerie.dart';
import 'package:taama_conducteur/widgets/alerte_sonnerie.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('taama/sonnerie_systeme');

  group('lecture', () {
    test('tout va bien : rien à signaler', () {
      expect(
        VerificationSonnerie.lire(
          notificationsActives: true,
          importanceCanal: Importance.max,
          etatSysteme: const {'sonnerieMuette': false, 'economieBatterie': false},
        ),
        isEmpty,
      );
    });

    test('chaque problème lu est signalé', () {
      expect(
        VerificationSonnerie.lire(
          notificationsActives: false,
          importanceCanal: null,
          etatSysteme: const {'sonnerieMuette': true, 'economieBatterie': true},
        ),
        ProblemeSonnerie.values,
      );
    });

    test('canal des demandes rendu silencieux par le chauffeur', () {
      expect(
        VerificationSonnerie.lire(
            notificationsActives: true, importanceCanal: Importance.low, etatSysteme: null),
        [ProblemeSonnerie.notificationsCoupees],
      );
    });

    test('rien de lisible : aucune alerte inventée', () {
      expect(
        VerificationSonnerie.lire(notificationsActives: null, importanceCanal: null, etatSysteme: null),
        isEmpty,
      );
    });
  });

  group('téléphone', () {
    final appels = <MethodCall>[];

    setUp(() {
      appels.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (appel) async {
        appels.add(appel);
        return switch (appel.method) {
          'etat' => {'sonnerieMuette': true, 'economieBatterie': false},
          'ouvrirReglages' => true,
          _ => null,
        };
      });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null);
    });

    test('état lu sur le téléphone', () async {
      expect(await VerificationSonnerie.verifier(), [ProblemeSonnerie.sonnerieMuette]);
    });

    test('« Régler » ouvre le bon réglage', () async {
      expect(await VerificationSonnerie.corriger(ProblemeSonnerie.economieBatterie), isTrue);
      expect(await VerificationSonnerie.corriger(ProblemeSonnerie.sonnerieMuette), isTrue);
      expect(await VerificationSonnerie.corriger(ProblemeSonnerie.notificationsCoupees), isTrue);
      expect(appels.map((a) => a.arguments['reglage']), ['batterie', 'son', 'notifications']);
    });

    test('réglages impossibles à ouvrir : le dire (faux)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, (_) async => throw PlatformException(code: 'x'));
      expect(await VerificationSonnerie.corriger(ProblemeSonnerie.economieBatterie), isFalse);
      expect(await VerificationSonnerie.verifier(), isEmpty, reason: 'illisible : non signalé');
    });
  });

  testWidgets('alerte : un « Régler » par problème, qui marche', (t) async {
    final regles = <ProblemeSonnerie>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AlerteSonnerie(problemes: ProblemeSonnerie.values, onRegler: regles.add),
        ),
      ),
    ));
    expect(find.text('Ton téléphone risque de ne pas sonner'), findsOneWidget);
    expect(find.text('Régler'), findsNWidgets(3));
    await t.tap(find.text('Régler').last);
    expect(regles, [ProblemeSonnerie.economieBatterie]);
    expect(t.takeException(), isNull);
  });
}
