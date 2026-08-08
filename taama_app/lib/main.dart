import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/api_config.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'theme/couleurs_taama.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      debugPrint('FLUTTER ERROR: ${details.exception}');
      debugPrint('STACK: ${details.stack}');
    };

    // Pour vérifier ce que l'APK utilise vraiment (le --dart-define a-t-il
    // bien été pris en compte au build ?) — à retrouver dans les logs.
    debugPrint('ApiConfig.baseUrl = ${ApiConfig.baseUrl}');
    debugPrint('ApiConfig.wsUrl   = ${ApiConfig.wsUrl}');

    // J'initialise Firebase avant de lancer l'app
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }

    // Je prépare le service de notifications (permissions, écouteurs...)
    try {
      await NotificationService.initialiser();
    } catch (e) {
      debugPrint('Notification service init error: $e');
    }

    // Je restaure la session précédente si un token a été sauvegardé
    try {
      await ApiService.chargerTokenPersiste();
    } catch (e) {
      debugPrint('Token restore error: $e');
    }

    runApp(const TaamaApp());
  }, (error, stack) {
    debugPrint('ZONE ERROR: $error');
    debugPrint('STACK: $stack');
  });
}

/// Configuration globale de mon application
class TaamaApp extends StatelessWidget {
  const TaamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taama',
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