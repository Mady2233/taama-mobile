import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';
import 'otp_verification_screen.dart';

class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key});

  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends State<EcranConnexion>
    with TickerProviderStateMixin {
  final TextEditingController _telController = TextEditingController();
  bool _enChargement = false;

  late AnimationController _entreeController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entreeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entreeController, curve: Curves.easeOutCubic,
    ));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entreeController, curve: Curves.easeIn),
    );
    _entreeController.forward();
  }

  @override
  void dispose() {
    _telController.dispose();
    _entreeController.dispose();
    super.dispose();
  }

  Future<void> _continuer() async {
    final tel = _telController.text.trim();
    if (tel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entre ton numéro de téléphone')));
      return;
    }

    setState(() => _enChargement = true);
    try {
      final code = await ApiService.demanderOtp(tel);
      debugPrint('OTP debug : $code');
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EcranVerificationOTP(numeroTelephone: tel),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            e.toString().replaceAll('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ── Fond gradient animé ──
          Container(
            height: size.height * 0.55,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF1C2B4A),
                  Color(0xFF3D2B6B),
                  Color(0xFF1C2B4A),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // ── Illustration Bamako (cercles + rues stylisées) ──
          Positioned(
            top: 0, left: 0, right: 0,
            height: size.height * 0.52,
            child: Stack(
              children: [
                // Cercles de fond
                Positioned(
                  top: -40, right: -60,
                  child: Container(
                    width: 250, height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CouleursTaama.terreCuite
                          .withValues(alpha: 0.15),
                    ),
                  ),
                ),
                Positioned(
                  top: 80, left: -80,
                  child: Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20, right: 20,
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CouleursTaama.or.withValues(alpha: 0.1),
                    ),
                  ),
                ),

                // Illustration Bamako stylisée (grille de rues)
                Positioned(
                  bottom: 30, left: 0, right: 0,
                  child: Opacity(
                    opacity: 0.12,
                    child: CustomPaint(
                      painter: _RuesBamakoPainter(),
                      size: Size(size.width, 200),
                    ),
                  ),
                ),

                // Logo + titre
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
                    child: Column(
                      children: [
                        // Logo
                        Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          child: CustomPaint(
                            painter: _LogoPainter(),
                            size: const Size(80, 80),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Nom app
                        const Text(
                          'taama',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.5,
                          ),
                        ),

                        // Slogan bilingue
                        Text(
                          'Covoiturage à Bamako',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: CouleursTaama.terreCuite
                                .withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '"An b\'a sɔrɔ — On y arrive ensemble"',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Stats rapides
                        const Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceEvenly,
                          children: [
                            _StatItem(
                                valeur: '500+',
                                label: 'Conducteurs',
                                emoji: '🚗'),
                            _StatItem(
                                valeur: '4.8★',
                                label: 'Note',
                                emoji: '⭐'),
                            _StatItem(
                                valeur: '100%',
                                label: 'Sécurisé',
                                emoji: '🛡️'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Panel de connexion ──
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SlideTransition(
              position: _slideAnim,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Titre connexion bilingue
                      const Text(
                        'Connexion',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: CouleursTaama.indigo,
                        ),
                      ),
                      Text(
                        'I ka don — Entre ton numéro',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Champ téléphone
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            // Indicatif Mali
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 16),
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                      color: Colors.grey.shade200),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Text('🇲🇱', style: TextStyle(fontSize: 18)),
                                  SizedBox(width: 6),
                                  Text('+223',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: CouleursTaama.indigo)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _telController,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500),
                                decoration: const InputDecoration(
                                  hintText: 'XX XX XX XX',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 14),
                                ),
                                onSubmitted: (_) => _continuer(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Bouton continuer
                      ElevatedButton(
                        onPressed: _enChargement ? null : _continuer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CouleursTaama.terreCuite,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(14)),
                          elevation: 3,
                          shadowColor: CouleursTaama.terreCuite
                              .withValues(alpha: 0.4),
                        ),
                        child: _enChargement
                            ? const SizedBox(
                                width: 24, height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white))
                            : const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text('Continuer',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward, size: 18),
                                ],
                              ),
                      ),

                      const SizedBox(height: 16),

                      // Mention légale bilingue
                      Text(
                        'En continuant, tu acceptes nos Conditions d\'utilisation\n'
                        'I ka taa ɲɛ, i bɛ an ka sariyaw lafi.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Widget stat
class _StatItem extends StatelessWidget {
  final String valeur, label, emoji;
  const _StatItem({
    required this.valeur,
    required this.label,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 2),
        Text(valeur,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10)),
      ],
    );
  }
}

// Dessine des rues stylisées de Bamako
class _RuesBamakoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Grille de rues horizontales
    for (int i = 0; i < 8; i++) {
      final y = size.height * i / 7;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Rues verticales
    for (int i = 0; i < 12; i++) {
      final x = size.width * i / 11;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Diagonale (Avenue de la Liberté)
    canvas.drawLine(
      const Offset(0, 0),
      Offset(size.width * 0.6, size.height),
      paint..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// Logo painter (réutilisé depuis splash)
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
      ..cubicTo(128 * sx, 278 * sy, 200 * sx, 296 * sy, 256 * sx, 344 * sy)
      ..cubicTo(312 * sx, 296 * sy, 384 * sx, 278 * sy, 402 * sx, 230 * sy);
    canvas.drawPath(path, paint);
    canvas.drawCircle(Offset(110 * sx, 230 * sy), 18 * sx,
        Paint()..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawCircle(Offset(402 * sx, 230 * sy), 18 * sx,
        Paint()..color = Colors.white.withValues(alpha: 0.9));
    canvas.drawCircle(Offset(256 * sx, 344 * sy), 15 * sx,
        Paint()..color = CouleursTaama.or);
  }

  @override
  bool shouldRepaint(_) => false;
}
