import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/couleurs_taama.dart';
import '../services/api_service.dart';
import 'onboarding_screen.dart';
import 'connexion_screen.dart';
import 'espace_chauffeur_screen.dart';

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

    // Vérifie si déjà connecté
    if (ApiService.estConnecte) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const EcranEspaceChauffeur(),
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
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _logoController, _textController, _bgController
        ]),
        builder: (context, _) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color.lerp(
                    Colors.white,
                    const Color(0xFF1C2B4A),
                    _bgOpacity.value,
                  )!,
                  Color.lerp(
                    Colors.white,
                    const Color(0xFF3D2B6B),
                    _bgOpacity.value,
                  )!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                // Cercles décoratifs animés
                Positioned(
                  top: -100 + (100 * _bgOpacity.value),
                  right: -80 + (80 * _bgOpacity.value),
                  child: Opacity(
                    opacity: _bgOpacity.value * 0.15,
                    child: Container(
                      width: 300, height: 300,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -80 + (80 * _bgOpacity.value),
                  left: -60 + (60 * _bgOpacity.value),
                  child: Opacity(
                    opacity: _bgOpacity.value * 0.1,
                    child: Container(
                      width: 250, height: 250,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: CouleursTaama.terreCuite,
                      ),
                    ),
                  ),
                ),

                // Contenu central
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo animé
                      Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Container(
                            width: 120, height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(26),
                              child: CustomPaint(
                                painter: _LogoPainter(),
                                size: const Size(120, 120),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Texte animé
                      SlideTransition(
                        position: _textSlide,
                        child: FadeTransition(
                          opacity: _textOpacity,
                          child: Column(
                            children: [
                              const Text(
                                'taama',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1,
                                ),
                              ),
                              Text(
                                'Espace Conducteur',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Slogan en Bambara
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: CouleursTaama.terreCuite
                                      .withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '"An b\'a sɔrɔ — On y arrive ensemble"',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
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

                // Loader en bas
                Positioned(
                  bottom: 60,
                  left: 0, right: 0,
                  child: FadeTransition(
                    opacity: _textOpacity,
                    child: Column(
                      children: [
                        SizedBox(
                          width: 40,
                          child: LinearProgressIndicator(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.2),
                            valueColor: const AlwaysStoppedAnimation(
                                Colors.white),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Chargement...',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
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

// Dessine le logo Taama sur le splash
class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 512;
    final sy = size.height / 512;

    final paint = Paint()
      ..color = CouleursTaama.terreCuite
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28 * sx
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(110 * sx, 230 * sy)
      ..cubicTo(
        128 * sx, 278 * sy,
        200 * sx, 296 * sy,
        256 * sx, 344 * sy,
      )
      ..cubicTo(
        312 * sx, 296 * sy,
        384 * sx, 278 * sy,
        402 * sx, 230 * sy,
      );
    canvas.drawPath(path, paint);

    canvas.drawCircle(
      Offset(110 * sx, 230 * sy), 22 * sx,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      Offset(402 * sx, 230 * sy), 22 * sx,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      Offset(256 * sx, 344 * sy), 18 * sx,
      Paint()..color = CouleursTaama.or,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
