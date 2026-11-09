// Pièce d'identité du client (facultative) : lecture du statut sans rien
// deviner, chaque état de l'écran, et bandeau d'accueil qu'on peut fermer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/models/verification_identite.dart';
import 'package:taama_app/screens/verification_identite_screen.dart';
import 'package:taama_app/widgets/invitation_identite.dart';

void main() {
  group('lecture', () {
    test('statuts du serveur', () {
      expect(statutIdentiteDepuis('non_soumis'), StatutIdentite.nonSoumis);
      expect(statutIdentiteDepuis('approuve'), StatutIdentite.approuve);
      expect(statutIdentiteDepuis('inconnu'), isNull);
      expect(statutIdentiteDepuis(null), isNull);
    });

    test('motif seulement pour un refus', () {
      final refusee = VerificationIdentite.depuisJson({'statut': 'refuse', 'motif_refus': 'Photo floue'})!;
      expect((refusee.motifRefus, refusee.peutEnvoyer), ('Photo floue', true));
      final verifiee = VerificationIdentite.depuisJson({'statut': 'approuve', 'motif_refus': 'x'})!;
      expect((verifiee.motifRefus, verifiee.peutEnvoyer), (null, false));
    });

    test('réponse inexploitable : rien d’inventé', () {
      expect(VerificationIdentite.depuisJson({'statut': 'bizarre'}), isNull);
      expect(VerificationIdentite.depuisJson('x'), isNull);
    });
  });

  group('écran', () {
    Future<List<String>> ouvrir(
      WidgetTester t, {
      bool chargement = false,
      String? erreur,
      VerificationIdentite? verification,
      bool envoi = false,
    }) async {
      final actions = <String>[];
      await t.binding.setSurfaceSize(const Size(420, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: EcranVerificationIdentite(
          chargement: chargement,
          erreur: erreur,
          verification: verification,
          envoiEnCours: envoi,
          onReessayer: () => actions.add('reessayer'),
          onPrendrePhoto: () => actions.add('photo'),
          onChoisirPhoto: () => actions.add('galerie'),
        ),
      ));
      return actions;
    }

    testWidgets('chargement', (t) async {
      await ouvrir(t, chargement: true);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('erreur : message et Réessayer', (t) async {
      final actions = await ouvrir(t, erreur: 'Impossible de joindre Taama.');
      expect(find.text('Impossible de joindre Taama.'), findsOneWidget);
      await t.tap(find.text('Réessayer'));
      expect(actions, ['reessayer']);
    });

    testWidgets('sans pièce : facultatif dit clairement, deux façons d’envoyer', (t) async {
      final actions = await ouvrir(t, verification: const VerificationIdentite(statut: StatutIdentite.nonSoumis));
      expect(find.textContaining('Facultatif'), findsOneWidget);
      expect(find.textContaining('jamais ta pièce'), findsOneWidget);
      await t.tap(find.text('Prendre une photo'));
      await t.tap(find.text('Choisir dans la galerie'));
      expect(actions, ['photo', 'galerie']);
    });

    testWidgets('vérifiée : aucun bouton d’envoi', (t) async {
      await ouvrir(t, verification: const VerificationIdentite(statut: StatutIdentite.approuve));
      expect(find.text('Identité vérifiée'), findsOneWidget);
      expect(find.text('Prendre une photo'), findsNothing);
    });

    testWidgets('refusée : motif et nouvel envoi', (t) async {
      await ouvrir(t, verification: const VerificationIdentite(statut: StatutIdentite.refuse, motifRefus: 'Photo floue'));
      expect(find.text('Motif : Photo floue'), findsOneWidget);
      expect(find.text('Envoyer une autre photo'), findsOneWidget);
    });

    testWidgets('envoi en cours : boutons coupés, état visible', (t) async {
      final actions = await ouvrir(t,
          verification: const VerificationIdentite(statut: StatutIdentite.enAttente), envoi: true);
      expect(find.text('Envoi en cours…'), findsOneWidget);
      await t.tap(find.text('Prendre une photo'));
      expect(actions, isEmpty);
    });
  });

  group('bandeau d’accueil', () {
    testWidgets('ouvre la vérification ou se ferme', (t) async {
      final actions = <String>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BandeauInvitationIdentite(
            invitation: InvitationIdentite.aRenvoyer,
            onOuvrir: () => actions.add('ouvrir'),
            onMasquer: () => actions.add('masquer'),
          ),
        ),
      ));
      expect(find.text('Ta pièce n’a pas pu être vérifiée'), findsOneWidget);
      await t.tap(find.text('Ta pièce n’a pas pu être vérifiée'));
      await t.tap(find.byTooltip('Masquer'));
      expect(actions, ['ouvrir', 'masquer']);
    });
  });
}
