// Attribution de la carte : texte fixé au build (CARTE_ATTRIBUTION), jamais
// un fournisseur écrit en dur.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/config/carte_config.dart';
import 'package:taama_app/widgets/couche_carte_taama.dart';

void main() {
  test('texte = CarteConfig.attribution, mention OSM par défaut', () {
    expect(AttributionCarteTaama.texte, CarteConfig.attribution);
    // Build de test, sans --dart-define : la mention minimale due à OSM.
    expect(AttributionCarteTaama.texte, '© OpenStreetMap contributors');
  });

  testWidgets('affichée, sans mention d\'un fournisseur abandonné', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: AttributionCarteTaama())));
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(find.textContaining('CARTO'), findsNothing);
  });
}
