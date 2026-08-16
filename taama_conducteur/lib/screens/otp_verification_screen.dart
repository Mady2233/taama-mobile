import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'espace_chauffeur_screen.dart';
import 'inscription_chauffeur_screen.dart';

/// Deuxième écran : Vérification du code OTP (app conducteur uniquement).
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
      // J'appelle mon backend pour vérifier le code et récupérer mon token
      await ApiService.verifierOtp(widget.numeroTelephone, code);

      // J'envoie le token FCM de cet appareil, pour pouvoir recevoir des
      // notifications push (échoue silencieusement si pas disponible, ex: web)
      if (NotificationService.token != null) {
        await ApiService.enregistrerTokenNotification(NotificationService.token!);
      }

      if (!mounted) return;

      // Toujours le flux conducteur ici : je vérifie d'abord si un profil
      // existe déjà — sinon, j'envoie vers le formulaire de création automatique.
      Widget ecranSuivant;
      try {
        await ApiService.monProfilChauffeur();
        ecranSuivant = const EcranEspaceChauffeur();
      } catch (e) {
        // Pas encore de profil chauffeur pour ce compte -> on le crée
        ecranSuivant = const EcranInscriptionChauffeur();
      }

      if (!mounted) return;

      // Navigation propre : on détruit l'historique et on affiche l'écran adapté
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => ecranSuivant),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vérification'),
        backgroundColor: Colors.transparent,
        elevation: 0, // Pour un design plat et dynamique
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Code de vérification',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // J'affiche le numéro pour confirmer à l'utilisateur
              Text(
                'Un code à 6 chiffres a été envoyé au ${widget.numeroTelephone}',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              // Mon champ de saisie OTP personnalisé
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6, // Je limite à 6 chiffres max
                style: const TextStyle(
                    fontSize: 28, letterSpacing: 16, fontWeight: FontWeight.bold),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ], // Uniquement des chiffres autorisés
                decoration: InputDecoration(
                  counterText: "", // Je cache le compteur "0/4" pour un look pro
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.amber, width: 2),
                  ),
                ),
              ),
              const Spacer(), // Je pousse le bouton tout en bas de mon écran
              ElevatedButton(
                onPressed: _enChargement ? null : _verifierEtContinuer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _enChargement
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Vérifier et Commencer',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
