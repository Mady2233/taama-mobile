// Prix ajustable de la demande entrante : prix au centre, − et + qui marchent,
// grisés à la limite, écart affiché, rien ne déborde sur un petit écran.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/utils/format.dart';
import 'package:taama_conducteur/widgets/selecteur_prix.dart';

void main() {
  Future<List<String>> ouvrir(
    WidgetTester t, {
    int prix = 1500,
    int ecart = 0,
    bool baisser = true,
    bool monter = true,
    double largeur = 360,
  }) async {
    final actions = <String>[];
    await t.binding.setSurfaceSize(Size(largeur, 400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: SelecteurPrix(
            prix: prix,
            ecart: ecart,
            pas: 100,
            surBaisser: baisser ? () => actions.add('baisser') : null,
            surMonter: monter ? () => actions.add('monter') : null,
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    return actions;
  }

  testWidgets('le prix au centre, entre − et +', (t) async {
    await ouvrir(t);
    final prix = t.getCenter(find.text(formaterFcfa(1500))).dx;
    expect(t.getCenter(find.byIcon(Icons.remove_rounded)).dx, lessThan(prix));
    expect(t.getCenter(find.byIcon(Icons.add_rounded)).dx, greaterThan(prix));
    expect(find.text('Prix standard'), findsOneWidget);
  });

  testWidgets('− et + appellent leur action', (t) async {
    final actions = await ouvrir(t);
    await t.tap(find.byIcon(Icons.remove_rounded));
    await t.tap(find.byIcon(Icons.add_rounded));
    expect(actions, ['baisser', 'monter']);
  });

  testWidgets('à la limite : bouton grisé, aucune action', (t) async {
    final actions = await ouvrir(t, monter: false);
    await t.tap(find.byIcon(Icons.add_rounded));
    expect(actions, isEmpty);
    expect(find.byTooltip('Monter le prix de ${formaterFcfa(100)}'), findsOneWidget);
  });

  testWidgets('écart affiché à la hausse comme à la baisse', (t) async {
    await ouvrir(t, prix: 1700, ecart: 200);
    expect(find.text('+${formaterFcfa(200)} sur le prix standard'), findsOneWidget);
    await ouvrir(t, prix: 1300, ecart: -200);
    expect(find.text('−${formaterFcfa(200)} sur le prix standard'), findsOneWidget);
  });

  testWidgets('petit écran et gros montant : rien ne déborde', (t) async {
    await ouvrir(t, prix: 125000, ecart: 20000, largeur: 300);
    expect(t.takeException(), isNull);
  });
}
