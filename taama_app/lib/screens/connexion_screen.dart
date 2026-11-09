import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/taama_theme.dart';
import '../widgets/taama/marque_taama.dart';
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
      // Le code n'est jamais écrit dans les journaux.
      await ApiService.demanderOtp(tel);
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
    return Scaffold(
      backgroundColor: TaamaColors.navy,
      resizeToAvoidBottomInset: true,
      body: FondMarque(
        // Hauteur de l'écran au moins ; clavier ouvert, tout défile.
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const LogoTaama(taille: 76),
                            const SizedBox(height: 18),
                            const NomTaama(taille: 40),
                            const SizedBox(height: 4),
                            Text(
                              'VTC et moto-taxi à Bamako',
                              style: TaamaText.body.copyWith(fontSize: 15, color: TaamaColors.onNavyMuted),
                            ),
                            const SizedBox(height: 22),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final (icone, texte) in promessesTaama)
                                  PastillePromesse(icone: icone, texte: texte),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SlideTransition(
                    position: _slideAnim,
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: _panneauConnexion(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panneauConnexion() {
    return Container(
      decoration: const BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connexion', style: TaamaText.title.copyWith(fontSize: 26)),
          const SizedBox(height: 4),
          Text(
            'I ka don — Entre ton numéro, on t’envoie un code.',
            style: TaamaText.muted.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),

          // Champ téléphone
          Container(
            decoration: BoxDecoration(
              color: TaamaColors.surfaceMuted,
              borderRadius: BorderRadius.circular(TaamaRadius.lg),
              border: Border.all(color: TaamaColors.border),
            ),
            child: Row(
              children: [
                Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: TaamaColors.surface,
                    borderRadius: BorderRadius.circular(TaamaRadius.md),
                    boxShadow: TaamaShadows.card,
                  ),
                  child: Row(
                    children: [
                      const Text('🇲🇱', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text('+223', style: TaamaText.body.copyWith(fontSize: 15, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _telController,
                    keyboardType: TextInputType.phone,
                    style: TaamaText.body.copyWith(fontSize: 17, letterSpacing: 0.5),
                    decoration: InputDecoration(
                      hintText: 'XX XX XX XX',
                      hintStyle: TaamaText.muted.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    ),
                    onSubmitted: (_) => _continuer(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bouton continuer
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _enChargement ? null : _continuer,
              style: FilledButton.styleFrom(
                textStyle: TaamaText.body.copyWith(fontSize: 16.5, fontWeight: FontWeight.w800),
              ),
              child: _enChargement
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: TaamaColors.textOnDark),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Continuer'),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 16),

          // Mention légale bilingue
          Text(
            'En continuant, tu acceptes nos Conditions d\'utilisation\n'
            'I ka taa ɲɛ, i bɛ an ka sariyaw lafi.',
            textAlign: TextAlign.center,
            style: TaamaText.muted.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.45),
          ),
        ],
      ),
    );
  }
}
