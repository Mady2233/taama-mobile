// Lien vers la politique de confidentialité : obligatoire dans l'app, jamais un
// bouton sans effet. L'adresse reste celle déclarée dans la fiche Google Play.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/config/app_config.dart';
import 'package:taama_conducteur/services/politique_confidentialite.dart';

Future<void> _ouvrirDepuisBouton(WidgetTester t, Future<bool> Function(Uri) ouvrir) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => ouvrirPolitiqueConfidentialite(context, ouvrir: ouvrir),
          child: const Text('ouvrir'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('ouvrir'));
  await t.pump();
}

void main() {
  test('adresse publique et stable, en https', () {
    expect(
      AppConfig.urlPolitiqueConfidentialite,
      'https://taama-backend-gt9i.onrender.com/politique-confidentialite/',
    );
  });

  testWidgets('la page s’ouvre : aucun message', (t) async {
    Uri? demandee;
    await _ouvrirDepuisBouton(t, (uri) async {
      demandee = uri;
      return true;
    });
    expect(demandee.toString(), AppConfig.urlPolitiqueConfidentialite);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('rien ne peut l’ouvrir : l’adresse est affichée', (t) async {
    await _ouvrirDepuisBouton(t, (_) async => false);
    expect(find.textContaining(AppConfig.urlPolitiqueConfidentialite), findsOneWidget);
  });

  testWidgets('erreur du système : l’adresse est affichée, sans plantage', (t) async {
    await _ouvrirDepuisBouton(t, (_) async => throw Exception('aucun navigateur'));
    expect(find.textContaining(AppConfig.urlPolitiqueConfidentialite), findsOneWidget);
  });

  test('l’écran propose le lien, branché', () {
    final ecran = File('lib/screens/espace_chauffeur_screen.dart').readAsStringSync();
    expect(ecran, contains('Politique de confidentialité'));
    expect(ecran, contains('ouvrirPolitiqueConfidentialite(context)'));
    expect(ecran, contains("case 'politique':"));
  });
}
