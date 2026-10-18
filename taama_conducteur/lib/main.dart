import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/api_config.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/demande_entrante_navigator.dart';
import 'services/notification_service.dart';
import 'theme/couleurs_taama.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pour vérifier ce que l'APK utilise vraiment (le --dart-define a-t-il
  // bien été pris en compte au build ?) — à retrouver dans les logs.
  debugPrint('ApiConfig.baseUrl = ${ApiConfig.baseUrl}');
  debugPrint('ApiConfig.wsUrl   = ${ApiConfig.wsUrl}');

  try {
    await Firebase.initializeApp();
    await NotificationService.initialiser();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  // Je restaure la session précédente si un token a été sauvegardé
  try {
    await ApiService.chargerTokenPersiste();
  } catch (e) {
    debugPrint('Token restore error: $e');
  }

  runApp(const TaamaConducApp());
}

class TaamaConducApp extends StatelessWidget {
  const TaamaConducApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Taama Conducteur',
      debugShowCheckedModeBanner: false,
      theme: _themeTaama,
      home: const EcranSplash(),
    );
  }
}

/// Thème global — même logique que taama_app/lib/main.dart (dupliqué par
/// convention, chaque app Flutter reste autonome) : donne un style
/// cohérent aux boutons/champs/cartes/AppBar par défaut sur tous les
/// écrans, plutôt que chaque écran ne redéfinisse sa propre apparence.
final ThemeData _themeTaama = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: CouleursTaama.terreCuite,
    primary: CouleursTaama.terreCuite,
    secondary: CouleursTaama.indigo,
  ),
  scaffoldBackgroundColor: CouleursTaama.sable,
  appBarTheme: const AppBarTheme(
    backgroundColor: CouleursTaama.sable,
    foregroundColor: CouleursTaama.indigo,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      color: CouleursTaama.indigo,
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    margin: EdgeInsets.zero,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: CouleursTaama.terreCuite,
      foregroundColor: Colors.white,
      elevation: 0,
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: CouleursTaama.indigo,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: CouleursTaama.indigo,
      minimumSize: const Size.fromHeight(52),
      side: const BorderSide(color: CouleursTaama.indigo, width: 1.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: CouleursTaama.terreCuite, width: 1.6),
    ),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: CouleursTaama.sable,
    selectedColor: CouleursTaama.terreCuite.withValues(alpha: 0.15),
    labelStyle: const TextStyle(color: CouleursTaama.indigo),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    ),
    side: BorderSide.none,
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: CouleursTaama.terreCuite,
    unselectedItemColor: CouleursTaama.grisTexte,
    type: BottomNavigationBarType.fixed,
    elevation: 8,
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFFE5DFD3),
    thickness: 1,
    space: 1,
  ),
);
