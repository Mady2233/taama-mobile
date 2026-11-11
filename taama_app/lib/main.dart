import 'dart:async';
import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:firebase_core/firebase_core.dart';
import 'carte/journal_sans_cle.dart';
import 'config/api_config.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/config_app.dart';
import 'services/enregistrement_jeton.dart';
import 'services/mise_a_jour.dart';
import 'services/navigation.dart';
import 'services/notification_service.dart';
import 'theme/taama_theme.dart';
import 'widgets/bandeau_mise_a_jour.dart';

void main() {
  // Avant tout le reste : aucune clé d'API dans les journaux.
  installerJournalSansCle();
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

    // Licences des polices embarquées (SIL OFL), dans la page des licences.
    LicenseRegistry.addLicense(() async* {
      for (final (police, fichier) in const [('Sora', 'OFL-Sora.txt'), ('Manrope', 'OFL-Manrope.txt')]) {
        yield LicenseEntryWithLineBreaks([police], await rootBundle.loadString('assets/fonts/$fichier'));
      }
    });

    // J'initialise Firebase avant de lancer l'app
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
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

    // Mode gratuit / paiement : valeur gardée tout de suite, serveur
    // interrogé sans retarder l'ouverture (voir ConfigApp).
    await ConfigApp.chargerValeurGardee();
    unawaited(ConfigApp.rafraichir());

    // Avant les premières requêtes : la version est annoncée au serveur.
    await MiseAJour.annoncerVersion();

    // Session ouverte : le jeton de notification est réenregistré à chaque
    // démarrage (réponse vérifiée, nouveaux essais : EnregistrementJeton).
    unawaited(EnregistrementJeton.enregistrer(NotificationService.token));

    runApp(const TaamaApp());
  }, (error, stack) {
    debugPrint('ZONE ERROR: $error');
    debugPrint('STACK: $stack');
  });
}

/// Configuration globale de mon application
class TaamaApp extends StatefulWidget {
  const TaamaApp({super.key});

  @override
  State<TaamaApp> createState() => _TaamaAppState();
}

class _TaamaAppState extends State<TaamaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Retour au premier plan : la version minimale a pu monter entre-temps.
  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (etat == AppLifecycleState.resumed) unawaited(MiseAJour.verifierAuRetour());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Taama',
      debugShowCheckedModeBanner: false,
      theme: TaamaTheme.light(),
      builder: (context, enfant) => AvecBandeauMiseAJour(child: enfant ?? const SizedBox.shrink()),
      home: const EcranSplash(),
    );
  }
}
