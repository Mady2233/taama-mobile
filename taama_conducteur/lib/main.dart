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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: CouleursTaama.terreCuite,
          primary: CouleursTaama.terreCuite,
          secondary: CouleursTaama.indigo,
        ),
        scaffoldBackgroundColor: CouleursTaama.sable,
        useMaterial3: true,
      ),
      home: const EcranSplash(),
    );
  }
}
