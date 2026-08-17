import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';

/// Écran de vérification du conducteur (KYC) : soumission des photos du
/// permis et de l'assurance, et suivi du statut de validation par l'admin.
class EcranVerificationConducteur extends StatefulWidget {
  const EcranVerificationConducteur({super.key});

  @override
  State<EcranVerificationConducteur> createState() => _EcranVerificationConducteurState();
}

class _EcranVerificationConducteurState extends State<EcranVerificationConducteur> {
  bool _chargement = true;
  bool _envoi = false;
  String _statut = 'non_soumis';
  bool _verifie = false;
  String _motifRefus = '';

  File? _photoPermis;
  File? _photoAssurance;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _chargerStatut();
  }

  Future<void> _chargerStatut() async {
    setState(() => _chargement = true);
    try {
      final donnees = await ApiService.statutVerification();
      if (!mounted) return;
      setState(() {
        _verifie = donnees['verifie'] as bool? ?? false;
        _statut = donnees['statut']?.toString() ?? 'non_soumis';
        _motifRefus = donnees['motif_refus']?.toString() ?? '';
      });
    } catch (e) {
      debugPrint('Erreur chargement statut vérification : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _choisirPhoto({required bool estPermis}) async {
    final image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image == null) return;
    setState(() {
      if (estPermis) {
        _photoPermis = File(image.path);
      } else {
        _photoAssurance = File(image.path);
      }
    });
  }

  Future<void> _soumettre() async {
    if (_photoPermis == null || _photoAssurance == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute les deux photos avant d\'envoyer.')),
      );
      return;
    }

    setState(() => _envoi = true);
    try {
      await ApiService.soumettreVerification(
        permis: _photoPermis!,
        assurance: _photoAssurance!,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documents envoyés ! Vérification en cours (24-48h).')),
      );
      await _chargerStatut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString().replaceAll("Exception: ", "")}')),
      );
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Widget _badgeStatut() {
    late Color couleur;
    late IconData icone;
    late String libelle;

    if (_verifie) {
      couleur = Colors.green;
      icone = Icons.check_circle;
      libelle = 'Vérifié';
    } else if (_statut == 'en_attente') {
      couleur = CouleursTaama.or;
      icone = Icons.hourglass_top;
      libelle = 'En attente de validation';
    } else if (_statut == 'refuse') {
      couleur = Colors.red;
      icone = Icons.cancel;
      libelle = 'Non vérifié';
    } else {
      couleur = Colors.red;
      icone = Icons.cancel;
      libelle = 'Non vérifié';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icone, color: couleur),
          const SizedBox(width: 10),
          Text(libelle, style: TextStyle(color: couleur, fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _carteChoixPhoto({
    required String titre,
    required File? photo,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: photo != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(photo, fit: BoxFit.cover, width: double.infinity),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.camera_alt, color: CouleursTaama.indigo, size: 32),
                  const SizedBox(height: 8),
                  Text(titre, style: const TextStyle(color: CouleursTaama.indigo, fontWeight: FontWeight.bold)),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vérification du profil'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: CouleursTaama.terreCuite))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _badgeStatut(),
                  if (_statut == 'refuse' && _motifRefus.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Motif du refus : $_motifRefus',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                  if (!_verifie) ...[
                    const SizedBox(height: 28),
                    const Text(
                      'Envoie une photo lisible de ton permis de conduire et de ton attestation d\'assurance. '
                      'La vérification prend généralement 24 à 48h.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    const Text('Permis de conduire', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _carteChoixPhoto(
                      titre: 'Prendre une photo du permis',
                      photo: _photoPermis,
                      onTap: () => _choisirPhoto(estPermis: true),
                    ),
                    const SizedBox(height: 20),
                    const Text('Attestation d\'assurance', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _carteChoixPhoto(
                      titre: 'Prendre une photo de l\'assurance',
                      photo: _photoAssurance,
                      onTap: () => _choisirPhoto(estPermis: false),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      onPressed: _envoi ? null : _soumettre,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CouleursTaama.terreCuite,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _envoi
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              _statut == 'refuse' ? 'Renvoyer les documents' : 'Envoyer pour vérification',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
