import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';

/// Écran de vérification du conducteur (KYC) : soumission des documents
/// requis selon le type de transport, et suivi du statut de validation par
/// l'admin.
class EcranVerificationConducteur extends StatefulWidget {
  const EcranVerificationConducteur({super.key});

  @override
  State<EcranVerificationConducteur> createState() => _EcranVerificationConducteurState();
}

class _EcranVerificationConducteurState extends State<EcranVerificationConducteur> {
  bool _chargement = true;
  bool _envoi = false;
  String? _erreurChargement;

  String _typeTransport = 'Voiture';
  String _statut = 'non_soumis';
  bool _aPhotoProfil = false;
  String _motifRefus = '';

  File? _piece;
  File? _permis;
  File? _assurance;
  File? _photo;
  final TextEditingController _controleurNumeroCaisse = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  bool get _estMoto => _typeTransport == 'Moto';

  @override
  void initState() {
    super.initState();
    _chargerProfil();
  }

  @override
  void dispose() {
    _controleurNumeroCaisse.dispose();
    super.dispose();
  }

  Future<void> _chargerProfil() async {
    setState(() {
      _chargement = true;
      _erreurChargement = null;
    });
    try {
      final profil = await ApiService.monProfilConducteur();
      final statut = profil['statut_verification']?.toString() ?? 'non_soumis';
      var motif = '';
      if (statut == 'refuse') {
        try {
          final donneesStatut = await ApiService.statutVerification();
          motif = donneesStatut['motif_refus']?.toString() ?? '';
        } catch (_) {
          // Complément d'affichage seulement : son absence ne bloque pas l'écran.
        }
      }
      if (!mounted) return;
      setState(() {
        _typeTransport = profil['type_transport']?.toString() ?? 'Voiture';
        _statut = statut;
        _aPhotoProfil = profil['a_photo_profil'] as bool? ?? false;
        _motifRefus = motif;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreurChargement = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _choisirPhoto(void Function(File) onChoisie) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir depuis la galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final image = await _picker.pickImage(source: source, imageQuality: 70);
    if (image == null) return;
    setState(() => onChoisie(File(image.path)));
  }

  Future<void> _soumettre() async {
    if (_piece == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute une photo de ta pièce d\'identité.')),
      );
      return;
    }
    if (_estMoto) {
      if (_controleurNumeroCaisse.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Renseigne ton numéro de caisse.')),
        );
        return;
      }
    } else {
      if (_permis == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoute une photo de ton permis de conduire.')),
        );
        return;
      }
      if (_assurance == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoute une photo de ton attestation d\'assurance.')),
        );
        return;
      }
    }
    if (!_aPhotoProfil && _photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute une photo de toi.')),
      );
      return;
    }

    setState(() => _envoi = true);
    try {
      await ApiService.soumettreVerification(
        piece: _piece!,
        permis: _permis,
        assurance: _assurance,
        photo: _photo,
        numeroCaisse: _estMoto ? _controleurNumeroCaisse.text.trim() : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documents reçus, vérification en cours (24-48h).')),
      );
      await _chargerProfil();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString().replaceAll("Exception: ", "")}')),
      );
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
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

  Widget _champ(String titre, Widget enfant) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titre, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          enfant,
        ],
      ),
    );
  }

  Widget _contenuEnAttente() {
    final documents = _estMoto ? "pièce d'identité, numéro de caisse" : "pièce d'identité, permis, assurance";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CouleursTaama.or.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.hourglass_top, color: CouleursTaama.or),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Vérification en cours (24-48h)',
                  style: TextStyle(color: CouleursTaama.or, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Documents déjà soumis : $documents.', style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _contenuApprouve() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 10),
          Text('Compte vérifié ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _formulaire() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_statut == 'refuse' && _motifRefus.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('Motif du refus : $_motifRefus', style: const TextStyle(color: Colors.red)),
          ),
          const SizedBox(height: 20),
        ],
        _champ(
          "Pièce d'identité",
          _carteChoixPhoto(
            titre: "Ajouter la pièce d'identité",
            photo: _piece,
            onTap: () => _choisirPhoto((f) => _piece = f),
          ),
        ),
        if (_estMoto)
          _champ(
            'Numéro de caisse',
            TextField(
              controller: _controleurNumeroCaisse,
              decoration: const InputDecoration(
                hintText: 'Ex. 1234',
                border: OutlineInputBorder(),
              ),
            ),
          )
        else ...[
          _champ(
            'Permis de conduire',
            _carteChoixPhoto(
              titre: 'Ajouter le permis',
              photo: _permis,
              onTap: () => _choisirPhoto((f) => _permis = f),
            ),
          ),
          _champ(
            "Attestation d'assurance",
            _carteChoixPhoto(
              titre: "Ajouter l'assurance",
              photo: _assurance,
              onTap: () => _choisirPhoto((f) => _assurance = f),
            ),
          ),
        ],
        if (!_aPhotoProfil)
          _champ(
            'Photo de toi',
            _carteChoixPhoto(
              titre: 'Ajouter ta photo',
              photo: _photo,
              onTap: () => _choisirPhoto((f) => _photo = f),
            ),
          ),
        const SizedBox(height: 8),
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
    );
  }

  Widget _corps() {
    if (_erreurChargement != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_erreurChargement!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _chargerProfil, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    final Widget contenu;
    if (_statut == 'en_attente') {
      contenu = _contenuEnAttente();
    } else if (_statut == 'approuve') {
      contenu = _contenuApprouve();
    } else {
      contenu = _formulaire();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: contenu,
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
          : _corps(),
    );
  }
}
