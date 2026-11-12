import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/deconnexion.dart';
import '../services/notification_service.dart';
import '../theme/taama_theme.dart';
import 'accueil_screen.dart';

/// Deuxième écran : Vérification du code OTP
class EcranVerificationOTP extends StatefulWidget {
  // Je reçois le numéro de téléphone de l'écran précédent
  final String numeroTelephone;

  const EcranVerificationOTP({
    super.key,
    required this.numeroTelephone,
  });

  @override
  State<EcranVerificationOTP> createState() => _EcranVerificationOTPState();
}

class _EcranVerificationOTPState extends State<EcranVerificationOTP> {
  // Mon contrôleur pour le code de vérification à 6 chiffres
  final TextEditingController _otpController = TextEditingController();

  // Pour afficher un loader pendant l'appel réseau
  bool _enChargement = false;

  @override
  void dispose() {
    // Je n'oublie pas de libérer mon contrôleur
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verifierEtContinuer() async {
    final code = _otpController.text;

    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entre le code à 6 chiffres complet')),
      );
      return;
    }

    setState(() => _enChargement = true);

    try {
      // Déconnexion restée en attente (réseau) : terminée avant d'ouvrir la
      // nouvelle session, jamais pendant (Deconnexion).
      await Deconnexion.reprendre();

      // J'appelle mon backend pour vérifier le code et récupérer mon token
      await ApiService.verifierOtp(widget.numeroTelephone, code);
      await Deconnexion.apresConnexion();

      // Jeton FCM de cet appareil, pour les notifications push : envoyé sans
      // retarder l'ouverture (réponse vérifiée, nouveaux essais espacés),
      // redemandé à Firebase s'il a été supprimé à la déconnexion.
      unawaited(NotificationService.reenregistrerJeton());

      if (!mounted) return;

      // Navigation propre : on détruit l'historique et on affiche la carte
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const EcranAccueil()),
        (Route<dynamic> route) => false, // false = on détruit tout l'historique
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code invalide ou expiré, réessaie')),
      );
      debugPrint('Erreur verifierOtp : $e');
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
  }

  /// « 76000000 » → « +223 76 00 00 00 », espaces insécables (jamais coupé en
  /// fin de ligne) ; tout autre format reste tel quel.
  String get _numeroAffiche {
    final chiffres = widget.numeroTelephone.replaceAll(RegExp(r'\D'), '');
    if (chiffres.length != 8) return widget.numeroTelephone;
    return ['+223', for (var i = 0; i < 8; i += 2) chiffres.substring(i, i + 2)].join(String.fromCharCode(0xA0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TaamaColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: TaamaColors.background,
        foregroundColor: TaamaColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: TaamaColors.primarySoft,
                    borderRadius: BorderRadius.circular(TaamaRadius.lg),
                  ),
                  child: const Icon(Icons.sms_rounded, size: 30, color: TaamaColors.primary),
                ),
              ),
              const SizedBox(height: 20),
              Text('Code de vérification', style: TaamaText.title.copyWith(fontSize: 26)),
              const SizedBox(height: 8),
              // J'affiche le numéro pour confirmer à l'utilisateur
              Text.rich(
                TextSpan(
                  text: 'Entre le code à 6 chiffres envoyé au ',
                  children: [
                    TextSpan(
                      text: _numeroAffiche,
                      style: TaamaText.body.copyWith(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                style: TaamaText.muted.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
              ),
              const SizedBox(height: 28),
              // Mon champ de saisie OTP personnalisé
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6, // Je limite à 6 chiffres max
                autofocus: true,
                style: TaamaText.title.copyWith(fontSize: 30, letterSpacing: 14),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ], // Uniquement des chiffres autorisés
                decoration: InputDecoration(
                  counterText: '', // Je cache le compteur « 0/6 »
                  hintText: '······',
                  hintStyle: TaamaText.title.copyWith(fontSize: 30, letterSpacing: 14, color: TaamaColors.border),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                ),
                onSubmitted: (_) => _verifierEtContinuer(),
              ),
              // Espacement fixe (pas de Spacer) : dans un SingleChildScrollView,
              // le contenu défile au lieu de déborder quand le clavier s'ouvre.
              const SizedBox(height: 24),
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _enChargement ? null : _verifierEtContinuer,
                  style: FilledButton.styleFrom(
                    textStyle: TaamaText.body.copyWith(fontSize: 16.5, fontWeight: FontWeight.w800),
                  ),
                  child: _enChargement
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: TaamaColors.textOnDark),
                        )
                      : const Text('Vérifier et commencer'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _enChargement ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: TaamaColors.primary,
                  minimumSize: const Size(0, 48),
                  textStyle: TaamaText.body.copyWith(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
                child: const Text('Modifier le numéro'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}