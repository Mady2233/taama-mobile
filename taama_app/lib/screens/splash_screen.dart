import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/taama_theme.dart';
import '../services/api_service.dart';
import '../services/mise_a_jour.dart';
import '../widgets/taama/marque_taama.dart';
import 'mise_a_jour_requise_page.dart';
import 'onboarding_screen.dart';
import 'connexion_screen.dart';
import 'accueil_screen.dart';

class EcranSplash extends StatefulWidget {
  const EcranSplash({super.key});

  @override
  State<EcranSplash> createState() => _EcranSplashState();
}

class _EcranSplashState extends State<EcranSplash>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _bgController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _bgOpacity;

  @override
  void initState() {
    super.initState();

    // Cache la barre de statut pour un effet plein écran
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _textController, curve: Curves.easeOut,
    ));

    _bgOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(_bgController);

    _demarrerAnimations();
  }

  Future<void> _demarrerAnimations() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _bgController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _textController.forward();

    // Attend la fin des animations puis navigue
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    // Restaure la barre de statut
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Version trop ancienne : l'app s'arrête ici, jamais pendant une course.
    if (await MiseAJour.doitBloquer()) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PageMiseAJourRequise()));
      return;
    }
    if (!mounted) return;

    // Vérifie si déjà connecté
    if (ApiService.estConnecte) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const EcranAccueil(),
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    } else {
      // Vérifie si premier lancement (onboarding)
      final premierLancement = await _estPremierLancement();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => premierLancement
              ? const EcranOnboarding()
              : const EcranConnexion(),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    }
  }

  Future<bool> _estPremierLancement() async {
    final prefs = await SharedPreferences.getInstance();
    final vu = prefs.getBool('onboarding_vu') ?? false;
    return !vu;
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TaamaColors.navy,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _logoController, _textController, _bgController
        ]),
        builder: (context, _) {
          return FondMarque(
            intensite: _bgOpacity.value,
            child: Stack(
              children: [
                // Logo, nom et promesse au centre
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: const LogoTaama(taille: 112),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SlideTransition(
                        position: _textSlide,
                        child: FadeTransition(
                          opacity: _textOpacity,
                          child: Column(
                            children: [
                              const NomTaama(taille: 52),
                              const SizedBox(height: 6),
                              Text(
                                'VTC et moto-taxi à Bamako',
                                style: TaamaText.body.copyWith(
                                  fontSize: 16,
                                  color: TaamaColors.onNavyMuted,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Slogan en bambara
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                                decoration: BoxDecoration(
                                  color: TaamaColors.textOnDark.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(TaamaRadius.pill),
                                  border: Border.all(color: TaamaColors.textOnDark.withValues(alpha: 0.14)),
                                ),
                                child: Text(
                                  '« An b\'a sɔrɔ » — On y arrive ensemble',
                                  style: TaamaText.body.copyWith(
                                    fontSize: 12.5,
                                    fontStyle: FontStyle.italic,
                                    color: TaamaColors.textOnDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Chargement en bas
                Positioned(
                  bottom: 56,
                  left: 0,
                  right: 0,
                  child: FadeTransition(
                    opacity: _textOpacity,
                    child: Center(
                      child: SizedBox(
                        width: 48,
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: TaamaColors.textOnDark.withValues(alpha: 0.15),
                          valueColor: const AlwaysStoppedAnimation(TaamaColors.accentMint),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
