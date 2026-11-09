import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/config_app.dart';
import '../theme/taama_theme.dart';
import '../widgets/taama/marque_taama.dart';
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

  // Mode gratuit (lu sur le serveur) : la page « Paiement / Recharge » ne
  // promet pas un portefeuille qu'on ne peut pas utiliser.
  late final List<_OnboardingData> _pages = [
    for (final page in _toutesLesPages)
      if (!page.paiement || ConfigApp.paiementActif.value) page,
  ];

  final List<_OnboardingData> _toutesLesPages = const [
    _OnboardingData(
      icone: Icons.map_rounded,
      icones: [Icons.two_wheeler_rounded, Icons.directions_car_rounded, Icons.inventory_2_rounded],
      accent: TaamaColors.routeNight,
      titreFr: 'Bamako à portée\nde main',
      titreBambara: 'Bamako bɛ e bolo\nla',
      descFr: 'Trouve un conducteur disponible\nprès de toi en quelques secondes.',
      descBambara: 'Sɔrɔ sigilen min bɛ i\nkɔrɔ joona.',
    ),
    _OnboardingData(
      icone: Icons.account_balance_wallet_rounded,
      icones: [Icons.phone_android_rounded, Icons.payments_rounded, Icons.check_circle_rounded],
      accent: TaamaColors.star,
      paiement: true,
      titreFr: 'Paiement sécurisé\nvia Mobile Money',
      titreBambara: 'Sɔngɔ san ka ɲɛ\nMobile Money fɛ',
      descFr: 'Recharge ton compte Taama\navec Orange Money, Moov ou Wave.',
      descBambara: 'I ka Taama compte\nkɛnɛya Orange, Moov\nwala Wave fɛ.',
    ),
    _OnboardingData(
      icone: Icons.shield_rounded,
      icones: [Icons.verified_user_rounded, Icons.my_location_rounded, Icons.sos_rounded],
      accent: TaamaColors.accentMint,
      titreFr: 'Voyagez en\ntoute sécurité',
      titreBambara: 'Taa k\'i kɛnɛya\nla hɛrɛ la',
      descFr: 'Conducteurs vérifiés, suivi GPS\nen temps réel et bouton SOS.',
      descBambara: 'Sigilanw sɛbɛnnen,\nGPS lajɛlen ani\nSOS bouton.',
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

  void _suivant() {
    if (_pageActuelle < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _terminer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final derniere = _pageActuelle == _pages.length - 1;
    final accent = _pages[_pageActuelle].accent;
    return Scaffold(
      backgroundColor: TaamaColors.navy,
      body: FondMarque(
        child: SafeArea(
          child: Column(
            children: [
              // Bouton passer (skip)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                  child: TextButton(
                    onPressed: _terminer,
                    style: TextButton.styleFrom(
                      foregroundColor: TaamaColors.onNavyMuted,
                      minimumSize: const Size(48, 48),
                      textStyle: TaamaText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Passer'),
                  ),
                ),
              ),

              // Pages
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (index) {
                    setState(() => _pageActuelle = index);
                    _animController.reset();
                    _animController.forward();
                  },
                  itemBuilder: (context, index) => FadeTransition(
                    opacity: _fadeAnim,
                    child: _PageOnboarding(data: _pages[index]),
                  ),
                ),
              ),

              // Indicateurs + bouton bas
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                child: Column(
                  children: [
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
                            color: estActif ? accent : TaamaColors.textOnDark.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        onPressed: _suivant,
                        style: FilledButton.styleFrom(
                          backgroundColor: TaamaColors.surface,
                          foregroundColor: TaamaColors.navy,
                          textStyle: TaamaText.body.copyWith(fontSize: 16.5, fontWeight: FontWeight.w800),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(derniere ? 'Commencer' : 'Suivant'),
                            const SizedBox(width: 8),
                            Icon(derniere ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageOnboarding extends StatelessWidget {
  const _PageOnboarding({required this.data});

  final _OnboardingData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: contraintes.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Illustration : grande icône dans un halo de la couleur de la page
              Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [data.accent.withValues(alpha: 0.35), data.accent.withValues(alpha: 0)],
                  ),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TaamaColors.textOnDark.withValues(alpha: 0.10),
                    border: Border.all(color: data.accent.withValues(alpha: 0.6), width: 2),
                  ),
                  child: Icon(data.icone, size: 54, color: TaamaColors.textOnDark),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final icone in data.icones)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: data.accent.withValues(alpha: 0.16),
                      ),
                      child: Icon(icone, size: 22, color: data.accent),
                    ),
                ],
              ),
              const SizedBox(height: 28),

              // Titre français
              Text(
                data.titreFr,
                textAlign: TextAlign.center,
                style: TaamaText.title.copyWith(
                  fontSize: 30,
                  height: 1.15,
                  color: TaamaColors.textOnDark,
                ),
              ),
              const SizedBox(height: 10),

              // Titre bambara
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: TaamaColors.textOnDark.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(TaamaRadius.sm),
                ),
                child: Text(
                  data.titreBambara,
                  textAlign: TextAlign.center,
                  style: TaamaText.body.copyWith(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.3,
                    color: TaamaColors.onNavyMuted,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Description française
              Text(
                data.descFr,
                textAlign: TextAlign.center,
                style: TaamaText.body.copyWith(
                  fontSize: 15.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: TaamaColors.textOnDark.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: 8),

              // Description bambara
              Text(
                data.descBambara,
                textAlign: TextAlign.center,
                style: TaamaText.body.copyWith(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  height: 1.35,
                  color: data.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingData {
  final IconData icone;
  final List<IconData> icones;
  final Color accent;
  final String titreFr;
  final String titreBambara;
  final String descFr;
  final String descBambara;

  /// Page liée au paiement dans l'app : masquée en mode gratuit.
  final bool paiement;

  const _OnboardingData({
    required this.icone,
    required this.icones,
    required this.accent,
    required this.titreFr,
    required this.titreBambara,
    required this.descFr,
    required this.descBambara,
    this.paiement = false,
  });
}
