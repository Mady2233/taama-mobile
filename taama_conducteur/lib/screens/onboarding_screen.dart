import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'connexion_screen.dart';

class EcranOnboarding extends StatefulWidget {
  const EcranOnboarding({super.key});

  @override
  State<EcranOnboarding> createState() => _EcranOnboardingState();
}

class _EcranOnboardingState extends State<EcranOnboarding>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _pageActuelle = 0;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  final List<_OnboardingData> _pages = [
    _OnboardingData(
      illustration: '🗺️',
      gradient: [const Color(0xFF1C2B4A), const Color(0xFF2D4A7A)],
      titreFr: 'Bamako à portée\nde main',
      titreBambara: 'Bamako bɛ e bolo\nla',
      descFr: 'Trouve un conducteur disponible\nprès de toi en quelques secondes.',
      descBambara: 'Sɔrɔ sigilen min bɛ i\nkɔrɔ joona.',
      emoji1: '🚗', emoji2: '🏍️', emoji3: '📦',
      accentColor: const Color(0xFF4A9EFF),
    ),
    _OnboardingData(
      illustration: '💳',
      gradient: [const Color(0xFFC8623D), const Color(0xFFD4844A)],
      titreFr: 'Paiement sécurisé\nvia Mobile Money',
      titreBambara: 'Sɔngɔ san ka ɲɛ\nMobile Money fɛ',
      descFr: 'Recharge ton compte Taama\navec Orange Money, Moov ou Wave.',
      descBambara: 'I ka Taama compte\nkɛnɛya Orange, Moov\nwala Wave fɛ.',
      emoji1: '📱', emoji2: '💰', emoji3: '✅',
      accentColor: const Color(0xFFFFD700),
    ),
    _OnboardingData(
      illustration: '🛡️',
      gradient: [const Color(0xFF1B5E20), const Color(0xFF2E7D32)],
      titreFr: 'Voyagez en\ntoute sécurité',
      titreBambara: 'Taa k\'i kɛnɛya\nla hɛrɛ la',
      descFr: 'Conducteurs vérifiés, suivi GPS\nen temps réel et bouton SOS.',
      descBambara: 'Sigilanw sɛbɛnnen,\nGPS lajɛlen ani\nSOS bouton.',
      emoji1: '✅', emoji2: '📍', emoji3: '🆘',
      accentColor: const Color(0xFF69F0AE),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _terminer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_vu', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const EcranConnexion(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, anim, __, child) =>
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Pages
          PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (index) {
              setState(() => _pageActuelle = index);
              _animController.reset();
              _animController.forward();
            },
            itemBuilder: (context, index) =>
                _buildPage(_pages[index]),
          ),

          // Bouton passer (skip)
          Positioned(
            top: 56, right: 20,
            child: TextButton(
              onPressed: _terminer,
              child: Text(
                'Passer',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ),
          ),

          // Indicateurs + bouton bas
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.4),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  // Points indicateurs
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) {
                      final estActif = i == _pageActuelle;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: estActif ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: estActif
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),

                  // Bouton suivant / commencer
                  GestureDetector(
                    onTap: () {
                      if (_pageActuelle < _pages.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        _terminer();
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _pageActuelle < _pages.length - 1
                                ? 'Suivant'
                                : 'Commencer',
                            style: TextStyle(
                              color: _pages[_pageActuelle].gradient[0],
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            _pageActuelle < _pages.length - 1
                                ? Icons.arrow_forward
                                : Icons.rocket_launch,
                            color: _pages[_pageActuelle].gradient[0],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(_OnboardingData data) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: data.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // Cercles décoratifs
          Positioned(
            top: -80, right: -60,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 150, left: -80,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),

          // Contenu
          Positioned.fill(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 160,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(32, 60, 32, 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Grande illustration emoji
                              Container(
                                width: 140, height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.15),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    data.illustration,
                                    style: const TextStyle(fontSize: 60),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Emojis secondaires animés
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [data.emoji1, data.emoji2, data.emoji3]
                                    .map((e) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          child: Text(e,
                                              style: const TextStyle(fontSize: 26)),
                                        ))
                                    .toList(),
                              ),

                              const SizedBox(height: 20),

                              // Titre français
                              Text(
                                data.titreFr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  height: 1.2,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 8),

                              // Titre Bambara (plus petit, italique)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  data.titreBambara,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    height: 1.3,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),

                              const SizedBox(height: 14),

                              // Description française
                              Text(
                                data.descFr,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),

                              const SizedBox(height: 6),

                              // Description Bambara
                              Text(
                                data.descBambara,
                                style: TextStyle(
                                  color: data.accentColor.withValues(alpha: 0.9),
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  height: 1.3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingData {
  final String illustration;
  final List<Color> gradient;
  final String titreFr;
  final String titreBambara;
  final String descFr;
  final String descBambara;
  final String emoji1, emoji2, emoji3;
  final Color accentColor;

  const _OnboardingData({
    required this.illustration,
    required this.gradient,
    required this.titreFr,
    required this.titreBambara,
    required this.descFr,
    required this.descBambara,
    required this.emoji1,
    required this.emoji2,
    required this.emoji3,
    required this.accentColor,
  });
}
