import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taama_conducteur/main.dart';
import 'package:taama_conducteur/screens/connexion_screen.dart';
import 'package:taama_conducteur/screens/onboarding_screen.dart';
import 'package:taama_conducteur/screens/splash_screen.dart';

/// Démarrage sans session : splash, puis onboarding au premier lancement,
/// connexion ensuite. Aucun appel réseau (préférences simulées).
Future<void> _demarrer(WidgetTester tester) async {
  await tester.pumpWidget(const TaamaConducApp());
  expect(find.byType(EcranSplash), findsOneWidget);
  await tester.pump(const Duration(seconds: 3)); // animations du splash (2,6 s)
  await tester.pump(const Duration(milliseconds: 700)); // transition en fondu
}

void main() {
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
}
