// Photo du chauffeur : affichée dans la barre de l'accueil, initiale en repli,
// et photo réduite avant l'envoi (le serveur n'en garde que 400 px).
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/widgets/widget_avatar_conducteur.dart';

Future<void> _avatar(WidgetTester t, String? url) => t.pumpWidget(MaterialApp(
      home: Scaffold(body: AvatarConducteur(photoUrl: url, nom: 'Mady T.', radius: 20)),
    ));

void main() {
  testWidgets('sans photo : initiale', (t) async {
    await _avatar(t, null);
    expect(find.text('M'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('URL vide : initiale, jamais d’image cassée', (t) async {
    await _avatar(t, '');
    expect(find.text('M'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('avec photo : image réseau', (t) async {
    await _avatar(t, 'https://photos.exemple/profils/chauffeur_1_a1b2c3d4.jpg');
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });

  test('la barre de l’accueil affiche la photo, et la suit quand elle change', () {
    final source = File('lib/screens/espace_chauffeur_screen.dart').readAsStringSync();
    expect(source, contains(RegExp(r"photoUrl: _?profil\??\['photo_profil'\]")));
    expect(source, contains("_profil?['photo_profil'] = profil['photo_profil']"));
  });

  test('photo de profil réduite avant l’envoi', () {
    final source = File('lib/screens/profil_chauffeur_screen.dart').readAsStringSync();
    expect(source, contains('maxWidth: 800'));
    expect(source, contains('maxHeight: 800'));
  });

  test('une photo perdue n’est reprise que si elle vient de cet écran, et après confirmation', () {
    final source = File('lib/screens/profil_chauffeur_screen.dart').readAsStringSync();
    final reprise = source.substring(
      source.indexOf('Future<void> _reprendrePhotoPerdue'),
      source.indexOf('Future<void> _choisirEtUploaderPhoto'),
    );
    final repere = reprise.indexOf('_cleChoixPhotoEnCours) != true');
    final recuperation = reprise.indexOf('retrieveLostData');
    final confirmation = reprise.indexOf('confirme == true');
    final envoi = reprise.indexOf('_envoyerPhoto');
    expect(repere, greaterThan(-1));
    expect(recuperation, greaterThan(repere));
    expect(confirmation, greaterThan(recuperation));
    expect(envoi, greaterThan(confirmation));
  });
}
