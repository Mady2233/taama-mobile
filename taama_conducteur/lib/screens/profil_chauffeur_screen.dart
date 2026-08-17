import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../widgets/widget_avatar_conducteur.dart';

/// Écran de profil côté conducteur : téléphone, nom modifiable, infos du
/// véhicule modifiables par le conducteur lui-même (type, marque, modèle,
/// couleur, plaque, climatisation), et historique complet de toutes ses
/// courses (réservations reçues + demandes instantanées).
class EcranProfilChauffeur extends StatefulWidget {
  const EcranProfilChauffeur({super.key});

  @override
  State<EcranProfilChauffeur> createState() => _EcranProfilChauffeurState();
}

class _EcranProfilChauffeurState extends State<EcranProfilChauffeur> {
  bool _chargement = true;
  Map<String, dynamic>? _compte; // Infos du compte utilisateur (téléphone, nom)
  Map<String, dynamic>? _chauffeur; // Infos du profil chauffeur (véhicule, plaque...)
  List<Map<String, dynamic>> _historique = [];

  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _nomController = TextEditingController();
  bool _modeEdition = false;
  bool _enregistrement = false;
  bool _uploadPhotoEnCours = false;
  final ImagePicker _picker = ImagePicker();

  // ─── Édition des infos véhicule ────────────────────────────────────────
  final TextEditingController _marqueVehiculeController = TextEditingController();
  final TextEditingController _modeleVehiculeController = TextEditingController();
  final TextEditingController _plaqueVehiculeController = TextEditingController();
  String? _typeVehiculeSelectionne;
  String? _couleurSelectionnee;
  bool _climatisationSelectionnee = false;
  bool _modeEditionVehicule = false;
  bool _enregistrementVehicule = false;

  // Correspond à Chauffeur.TYPE_VEHICULE_CHOICES (backend).
  static const Map<String, String> _typesVehicule = {
    'MOTO': 'Moto',
    'BERLINE': 'Berline',
    '4X4': '4x4 / SUV',
    'TRICYCLE': 'Tricycle',
  };

  // Correspond à Chauffeur.COULEUR_CHOICES (backend).
  static const Map<String, String> _couleurs = {
    'BLANC': 'Blanc',
    'NOIR': 'Noir',
    'GRIS': 'Gris',
    'ARGENT': 'Argent',
    'ROUGE': 'Rouge',
    'BLEU': 'Bleu',
    'VERT': 'Vert',
    'JAUNE': 'Jaune',
    'MARRON': 'Marron',
    'BEIGE': 'Beige',
    'AUTRE': 'Autre',
  };

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _prenomController.dispose();
    _nomController.dispose();
    _marqueVehiculeController.dispose();
    _modeleVehiculeController.dispose();
    _plaqueVehiculeController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final compte = await ApiService.monProfil();
      final chauffeur = await ApiService.monProfilChauffeur();
      final reservations = await ApiService.historiqueReservationsChauffeur();
      final demandes = await ApiService.historiqueDemandesChauffeur();

      final combine = <Map<String, dynamic>>[
        ...reservations.map((r) => {...r as Map<String, dynamic>, '_type': 'reservation'}),
        ...demandes.map((d) => {...d as Map<String, dynamic>, '_type': 'demande'}),
      ];
      combine.sort((a, b) {
        final dateA = DateTime.tryParse(a['cree_le'] ?? '') ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['cree_le'] ?? '') ?? DateTime(2000);
        return dateB.compareTo(dateA);
      });

      if (!mounted) return;
      setState(() {
        _compte = compte;
        _chauffeur = chauffeur;
        _historique = combine;
        _prenomController.text = compte['first_name'] ?? '';
        _nomController.text = compte['last_name'] ?? '';
      });
    } catch (e) {
      debugPrint('Erreur chargement profil chauffeur : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _choisirEtUploaderPhoto() async {
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

    final image = await _picker.pickImage(source: source, imageQuality: 85);
    if (image == null) return;

    setState(() => _uploadPhotoEnCours = true);
    try {
      final chauffeur = await ApiService.uploaderPhotoProfil(File(image.path));
      if (!mounted) return;
      setState(() => _chauffeur = {...?_chauffeur, ...chauffeur});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _uploadPhotoEnCours = false);
    }
  }

  Future<void> _enregistrerProfil() async {
    setState(() => _enregistrement = true);
    try {
      final compte = await ApiService.modifierProfil(
        prenom: _prenomController.text.trim(),
        nom: _nomController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _compte = compte;
        _modeEdition = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la mise à jour')),
      );
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  void _debuterEditionVehicule() {
    _marqueVehiculeController.text = _chauffeur?['marque']?.toString() ?? '';
    _modeleVehiculeController.text = _chauffeur?['modele']?.toString() ?? '';
    _plaqueVehiculeController.text = _chauffeur?['plaque']?.toString() ?? '';
    final typeVehiculeActuel = _chauffeur?['type_vehicule']?.toString();
    final couleurActuelle = _chauffeur?['couleur']?.toString();
    setState(() {
      _typeVehiculeSelectionne = (typeVehiculeActuel?.isNotEmpty ?? false) ? typeVehiculeActuel : null;
      _couleurSelectionnee = (couleurActuelle?.isNotEmpty ?? false) ? couleurActuelle : null;
      _climatisationSelectionnee = _chauffeur?['climatisation'] as bool? ?? false;
      _modeEditionVehicule = true;
    });
  }

  Future<void> _enregistrerVehicule() async {
    if (_typeVehiculeSelectionne == null || _couleurSelectionnee == null ||
        _marqueVehiculeController.text.trim().isEmpty ||
        _modeleVehiculeController.text.trim().isEmpty ||
        _plaqueVehiculeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remplis tous les champs du véhicule')),
      );
      return;
    }

    setState(() => _enregistrementVehicule = true);
    try {
      final chauffeur = await ApiService.modifierMonVehicule(
        typeVehicule: _typeVehiculeSelectionne,
        marque: _marqueVehiculeController.text.trim(),
        modele: _modeleVehiculeController.text.trim(),
        couleur: _couleurSelectionnee,
        plaque: _plaqueVehiculeController.text.trim(),
        climatisation: _climatisationSelectionnee,
      );
      if (!mounted) return;
      setState(() {
        _chauffeur = {...?_chauffeur, ...chauffeur};
        _modeEditionVehicule = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Véhicule mis à jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _enregistrementVehicule = false);
    }
  }

  (IconData, String, String, Color) _infosEntree(Map<String, dynamic> entree) {
    if (entree['_type'] == 'reservation') {
      final trajet = entree['trajet_propose'];
      final statut = entree['statut']?.toString() ?? '';
      final couleur = switch (statut) {
        'confirmee' => Colors.green,
        'refusee' => Colors.red,
        'annulee' => Colors.grey,
        _ => Colors.orange,
      };
      return (
        Icons.event_seat,
        '${trajet['depart']} → ${trajet['arrivee']}',
        'Réservation reçue • ${trajet['prix_par_place']} FCFA',
        couleur,
      );
    } else {
      final statut = entree['statut']?.toString() ?? '';
      final couleur = switch (statut) {
        'termine' => Colors.green,
        'annule' => Colors.grey,
        'en_route' || 'client_a_bord' => Colors.blue,
        _ => Colors.orange,
      };
      return (
        Icons.flash_on,
        entree['destination']?.toString() ?? '',
        'Demande instantanée • ${entree['prix_estime']} FCFA',
        couleur,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mon profil conducteur'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : RefreshIndicator(
              onRefresh: _charger,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Carte d'identité
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _uploadPhotoEnCours ? null : _choisirEtUploaderPhoto,
                              child: Stack(
                                children: [
                                  _uploadPhotoEnCours
                                      ? const SizedBox(
                                          width: 64,
                                          height: 64,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                                        )
                                      : AvatarConducteur(
                                          photoUrl: _chauffeur?['photo_profil'] as String?,
                                          nom: _chauffeur?['nom']?.toString() ?? '',
                                          radius: 32,
                                        ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.amber,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.camera_alt, size: 14, color: Colors.black),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _compte?['telephone'] ?? '',
                                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (_compte?['first_name']?.toString().isNotEmpty == true ||
                                            _compte?['last_name']?.toString().isNotEmpty == true)
                                        ? '${_compte?['first_name'] ?? ''} ${_compte?['last_name'] ?? ''}'.trim()
                                        : (_chauffeur?['nom'] ?? 'Nom non renseigné'),
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(_modeEdition ? Icons.close : Icons.edit, color: Colors.grey.shade700),
                              onPressed: () => setState(() => _modeEdition = !_modeEdition),
                            ),
                          ],
                        ),
                        if (_modeEdition) ...[
                          const SizedBox(height: 20),
                          TextField(
                            controller: _prenomController,
                            decoration: const InputDecoration(labelText: 'Prénom', border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nomController,
                            decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _enregistrement ? null : _enregistrerProfil,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                            child: _enregistrement
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                  )
                                : const Text('Enregistrer'),
                          ),
                        ],
                        if (_chauffeur != null) ...[
                          const Divider(height: 28),
                          Row(
                            children: [
                              Icon(Icons.directions_car, size: 18, color: Colors.grey.shade600),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_chauffeur!['type_transport']} • '
                                  '${_chauffeur!['marque'] ?? ''} ${_chauffeur!['modele'] ?? ''} • '
                                  '${_chauffeur!['plaque']}',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _modeEditionVehicule ? Icons.close : Icons.edit,
                                  size: 20, color: Colors.grey.shade700,
                                ),
                                onPressed: () {
                                  if (_modeEditionVehicule) {
                                    setState(() => _modeEditionVehicule = false);
                                  } else {
                                    _debuterEditionVehicule();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.star, size: 18, color: Colors.amber),
                              const SizedBox(width: 8),
                              Text(
                                'Note : ${_chauffeur!['note']}',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                          if (!_modeEditionVehicule) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Couleur : ${_couleurs[_chauffeur!['couleur']] ?? 'non renseignée'}'
                              '${(_chauffeur!['climatisation'] as bool? ?? false) ? ' • Climatisée' : ''}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                          ],
                          if (_modeEditionVehicule) ...[
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _typeVehiculeSelectionne,
                              decoration: const InputDecoration(labelText: 'Type de véhicule', border: OutlineInputBorder()),
                              items: _typesVehicule.entries
                                  .map((entree) => DropdownMenuItem(value: entree.key, child: Text(entree.value)))
                                  .toList(),
                              onChanged: (valeur) => setState(() => _typeVehiculeSelectionne = valeur),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _marqueVehiculeController,
                              decoration: const InputDecoration(labelText: 'Marque (ex: Toyota)', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _modeleVehiculeController,
                              decoration: const InputDecoration(labelText: 'Modèle (ex: Corolla)', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _couleurSelectionnee,
                              decoration: const InputDecoration(labelText: 'Couleur', border: OutlineInputBorder()),
                              items: _couleurs.entries
                                  .map((entree) => DropdownMenuItem(value: entree.key, child: Text(entree.value)))
                                  .toList(),
                              onChanged: (valeur) => setState(() => _couleurSelectionnee = valeur),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _plaqueVehiculeController,
                              decoration: const InputDecoration(labelText: 'Plaque d\'immatriculation', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 4),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Véhicule climatisé'),
                              value: _climatisationSelectionnee,
                              onChanged: (valeur) => setState(() => _climatisationSelectionnee = valeur),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _enregistrementVehicule ? null : _enregistrerVehicule,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                              child: _enregistrementVehicule
                                  ? const SizedBox(
                                      width: 18, height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                    )
                                  : const Text('Enregistrer le véhicule'),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text('Historique des courses', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  if (_historique.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('Aucune course pour l\'instant.', style: TextStyle(color: Colors.grey.shade500)),
                    )
                  else
                    ..._historique.map((entree) {
                      final (icone, titre, sousTitre, couleur) = _infosEntree(entree);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: couleur.withValues(alpha: 0.15),
                              child: Icon(icone, color: couleur, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(titre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text(sousTitre, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}