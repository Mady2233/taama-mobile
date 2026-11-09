// « Ton offre » : limites du serveur lues sans rien inventer, − et + bornés,
// montants d'un toucher, commande au prix choisi, rien ne déborde.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/models/service_course.dart';
import 'package:taama_app/utils/format.dart';
import 'package:taama_app/widgets/choix_offre.dart';

const _limites = OffreLimites(standard: 1450, min: 1250, max: 1650, pas: 100);

Future<List<int>> _feuille(WidgetTester t, {double largeur = 393}) async {
  final commandes = <int>[];
  await t.binding.setSurfaceSize(Size(largeur, 800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: FeuilleOffre(nomService: 'Berline', limites: _limites, onCommander: commandes.add),
      ),
    ),
  ));
  return commandes;
}

void main() {
  group('limites du serveur', () {
    test('lues telles quelles', () {
      final l = OffreLimites.depuisJson({'standard': 1450, 'min': 1250, 'max': 1650, 'pas': 100})!;
      expect((l.standard, l.min, l.max, l.pas), (1450, 1250, 1650, 100));
      expect(l.raccourcis, [1250, 1350, 1450, 1550]);
    });

    test('absentes ou incohérentes : pas de choix d’offre', () {
      expect(OffreLimites.depuisJson(null), isNull);
      expect(OffreLimites.depuisJson({'standard': 1450, 'min': 1250, 'max': 1650}), isNull);
      expect(OffreLimites.depuisJson({'standard': 1450, 'min': 1500, 'max': 1650, 'pas': 100}), isNull);
      expect(OffreLimites.depuisJson({'standard': 1450, 'min': 1260, 'max': 1650, 'pas': 100}), isNull);
      expect(OffreLimites.depuisJson({'standard': 1450, 'min': 1250, 'max': 1650, 'pas': 0}), isNull);
    });

    test('le service lit son offre, ou rien', () {
      final base = {'id': 3, 'nom': 'Berline', 'prix': 1450, 'devis_id': 9};
      expect(ServiceCourse.fromJson({...base, 'offre': {'standard': 1450, 'min': 1250, 'max': 1650, 'pas': 100}}).offre,
          isNotNull);
      expect(ServiceCourse.fromJson({...base, 'offre': null}).offre, isNull);
      expect(ServiceCourse.fromJson(base).offre, isNull);
    });
  });

  group('feuille', () {
    testWidgets('part du standard, commande au prix choisi', (t) async {
      final commandes = await _feuille(t);
      expect(find.text('Prix standard'), findsOneWidget);
      await t.tap(find.byTooltip('Baisser de ${formaterFcfa(100)}'));
      await t.tap(find.byTooltip('Baisser de ${formaterFcfa(100)}'));
      await t.pump();
      expect(find.text('−${formaterFcfa(200)} sur le standard'), findsOneWidget);
      await t.tap(find.text('Commander · ${formaterFcfa(1250)}'));
      expect(commandes, [1250]);
    });

    testWidgets('jamais au-delà des limites', (t) async {
      final commandes = await _feuille(t);
      for (var i = 0; i < 5; i++) {
        await t.tap(find.byTooltip('Monter de ${formaterFcfa(100)}'));
        await t.pump();
      }
      await t.tap(find.textContaining('Commander'));
      expect(commandes, [1650]);
    });

    testWidgets('montants d’un toucher', (t) async {
      final commandes = await _feuille(t);
      await t.tap(find.text(formaterFcfa(1350)));
      await t.pump();
      await t.tap(find.textContaining('Commander'));
      expect(commandes, [1350]);
    });

    testWidgets('offre plus basse : le client sait qu’un chauffeur peut refuser', (t) async {
      await _feuille(t);
      await t.tap(find.text(formaterFcfa(1250)));
      await t.pump();
      expect(find.textContaining('peut l’accepter, la refuser'), findsOneWidget);
    });

    testWidgets('petit écran : rien ne déborde', (t) async {
      await _feuille(t, largeur: 320);
      expect(t.takeException(), isNull);
    });
  });
}
