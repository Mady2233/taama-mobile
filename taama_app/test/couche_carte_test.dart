// Couche de quartiers et repères : pas de chevauchement (entre étiquettes,
// avec l'attribution, avec le bord), densité réduite en navigation, repères
// déjà dessinés par le fond masqués. Même fichier dans taama_app et
// taama_conducteur (seuls les imports diffèrent).
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:taama_app/donnees/carte_bamako.dart';
import 'package:taama_app/widgets/couche_carte_taama.dart';

const _centreBamako = LatLng(12.6460, -7.9990);
const _taille = Size(400, 700);

Future<void> _carte(WidgetTester t, Widget couche, {double zoom = 15.2}) async {
  await t.binding.setSurfaceSize(_taille);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FlutterMap(
        options: MapOptions(initialCenter: _centreBamako, initialZoom: zoom),
        children: [couche, const AttributionCarteTaama()],
      ),
    ),
  ));
  await t.pump();
}

/// Étiquettes affichées : (texte, rectangle à l'écran). Pour un repère, le
/// rectangle couvre la pastille et le nom.
List<(String, Rect)> _etiquettes(WidgetTester t) {
  final couche = find.byType(CoucheCarteTaama);
  return [
    for (final e in find.descendant(of: couche, matching: find.byType(Text)).evaluate())
      (
        (e.widget as Text).data!,
        () {
          final ligne = find.ancestor(of: find.byWidget(e.widget), matching: find.byType(Row));
          return ligne.evaluate().isNotEmpty ? t.getRect(ligne.first) : t.getRect(find.byWidget(e.widget));
        }(),
      ),
  ];
}

void main() {
  group('categoriesDuFond', () {
    test('noms séparés par des virgules, espaces tolérés', () {
      expect(categoriesDuFond('pharmacie, banque'),
          {CategorieRepere.pharmacie, CategorieRepere.banque});
    });
    test('vide ou inconnu : aucune catégorie, jamais une erreur', () {
      expect(categoriesDuFond(''), isEmpty);
      expect(categoriesDuFond('inconnu,,  '), isEmpty);
    });
  });

  testWidgets('aucun chevauchement : entre étiquettes, avec l\'attribution, avec le bord',
      (t) async {
    await _carte(t, const CoucheCarteTaama(reperesMasques: {}));
    final etiquettes = _etiquettes(t);
    expect(etiquettes.length, greaterThan(3), reason: 'la vue doit montrer des étiquettes');

    for (var i = 0; i < etiquettes.length; i++) {
      for (var j = i + 1; j < etiquettes.length; j++) {
        expect(etiquettes[i].$2.overlaps(etiquettes[j].$2), isFalse,
            reason: '${etiquettes[i].$1} / ${etiquettes[j].$1}');
      }
    }
    final attribution = t.getRect(find.text(AttributionCarteTaama.texte));
    final ecran = Offset.zero & _taille;
    for (final (nom, rect) in etiquettes) {
      expect(rect.overlaps(attribution), isFalse, reason: '$nom sous l\'attribution');
      expect(ecran.contains(rect.topLeft) && ecran.contains(rect.bottomRight - const Offset(1, 1)),
          isTrue, reason: '$nom coupé par le bord');
    }
  });

  testWidgets('navigation : au plus 12 étiquettes, grands quartiers et grands repères seulement',
      (t) async {
    await _carte(t, const CoucheCarteTaama(reperesMasques: {}));
    final normale = _etiquettes(t).length;

    await _carte(t, const CoucheCarteTaama(
        densite: DensiteEtiquettes.navigation, reperesMasques: {}));
    final navigation = _etiquettes(t);
    expect(navigation.length, lessThanOrEqualTo(12));
    expect(navigation.length, lessThan(normale), reason: 'densité réduite');

    final permis = {
      for (final q in quartiersBamako.where((q) => q.principal)) q.nom.toUpperCase(),
      for (final r in reperesBamako.where((r) => importanceRepere[r.categorie] == 1)) r.nom,
    };
    for (final (nom, _) in navigation) {
      expect(permis.contains(nom), isTrue, reason: '« $nom » ne devrait pas apparaître en navigation');
    }
  });

  testWidgets('repères dessinés par le fond : jamais répétés', (t) async {
    await _carte(t, CoucheCarteTaama(reperesMasques: CategorieRepere.values.toSet()));
    final quartiers = {for (final q in quartiersBamako) q.nom.toUpperCase()};
    for (final (nom, _) in _etiquettes(t)) {
      expect(quartiers.contains(nom), isTrue, reason: 'repère « $nom » affiché malgré le masque');
    }
  });

  testWidgets('sous le zoom 12 : aucune étiquette', (t) async {
    await _carte(t, const CoucheCarteTaama(), zoom: 11);
    expect(_etiquettes(t), isEmpty);
  });
}
