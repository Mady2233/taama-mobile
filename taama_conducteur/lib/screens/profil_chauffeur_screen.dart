import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/deconnexion.dart';
import '../services/fin_de_session.dart';
import '../theme/couleurs_taama.dart';
import '../widgets/dialogue_suppression_compte.dart';
import '../widgets/widget_avatar_conducteur.dart';
import 'connexion_screen.dart';
import 'mes_courses_page.dart';

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

  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _nomController = TextEditingController();
  bool _modeEdition = false;
  bool _enregistrement = false;
  bool _uploadPhotoEnCours = false;
  final ImagePicker _picker = ImagePicker();
  // Posé le temps du choix d'une photo de profil. retrieveLostData renvoie la
  // dernière image de TOUS les écrans : sans ce repère, un document KYC perdu
  // pourrait être proposé comme photo de profil, qui est publique.
  static const String _cleChoixPhotoEnCours = 'photo_profil_choix_en_cours';

  // ─── Édition des infos véhicule ────────────────────────────────────────
  final TextEditingController _marqueVehiculeController = TextEditingController();
  final TextEditingController _modeleVehiculeController = TextEditingController();
  final TextEditingController _plaqueVehiculeController = TextEditingController();
  String? _typeVehiculeSelectionne;
  String? _couleurSelectionnee;
  bool _climatisationSelectionnee = false;
  bool _modeEditionVehicule = false;
  bool _enregistrementVehicule = false;
  bool _suppressionEnCours = false;

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
    _reprendrePhotoPerdue();
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

      if (!mounted) return;
      setState(() {
        _compte = compte;
        _chauffeur = chauffeur;
        _prenomController.text = compte['first_name'] ?? '';
        _nomController.text = compte['last_name'] ?? '';
      });
    } catch (e) {
      debugPrint('Erreur chargement profil chauffeur : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  /// Sur un téléphone à court de mémoire, Android peut fermer l'app pendant
  /// que l'appareil photo est ouvert : la photo n'arrive jamais à pickImage.
  /// On la retrouve ici, et le chauffeur confirme avant tout envoi.
  Future<void> _reprendrePhotoPerdue() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_cleChoixPhotoEnCours) != true) return;
      await prefs.remove(_cleChoixPhotoEnCours);

      final fichier = (await _picker.retrieveLostData()).file;
      if (fichier == null || !mounted) return;

      final confirme = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Utiliser cette photo ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(fichier.path), height: 160, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
              const Text('Elle sera visible par vos clients.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Utiliser'),
            ),
          ],
        ),
      );
      if (confirme == true && mounted) await _envoyerPhoto(fichier);
    } catch (e) {
      debugPrint('[ProfilChauffeur] Erreur reprise photo : $e');
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cleChoixPhotoEnCours, true);

    XFile? image;
    try {
      image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        // Le serveur ne garde que 400 px : inutile d'envoyer plusieurs Mo,
        // trop long sur un réseau lent, et cher en data pour le chauffeur.
        maxWidth: 800,
        maxHeight: 800,
      );
    } catch (e) {
      // pickImage peut lever (permission refusée, pas d'appareil photo
      // disponible, etc.) — avant ce correctif, rien n'était affiché à
      // l'écran dans ce cas, juste un plantage silencieux en debug.
      debugPrint('[ProfilChauffeur] Erreur sélection photo ($source) : $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          source == ImageSource.camera
              ? 'Impossible d\'accéder à l\'appareil photo. Vérifie la permission dans les paramètres du téléphone.'
              : 'Impossible d\'accéder à la galerie. Vérifie la permission dans les paramètres du téléphone.',
        )),
      );
      return;
    } finally {
      await prefs.remove(_cleChoixPhotoEnCours);
    }
    if (image == null) {
      // Sélection annulée par l'utilisateur (retour sans choisir) — état
      // normal, pas une erreur, mais utile à distinguer dans les logs du
      // cas ci-dessus pendant le diagnostic.
      debugPrint('[ProfilChauffeur] Sélection annulée ($source).');
      return;
    }
    debugPrint('[ProfilChauffeur] Photo sélectionnée : ${image.path}');
    if (!mounted) return;
    await _envoyerPhoto(image);
  }

  Future<void> _envoyerPhoto(XFile image) async {
    setState(() => _uploadPhotoEnCours = true);
    try {
      final chauffeur = await ApiService.uploaderPhotoProfil(File(image.path));
      debugPrint('[ProfilChauffeur] Photo envoyée avec succès : ${chauffeur['photo_profil']}');
      if (!mounted) return;
      setState(() => _chauffeur = {...?_chauffeur, ...chauffeur});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo enregistrée.')),
      );
    } catch (e) {
      debugPrint('[ProfilChauffeur] Erreur envoi photo : $e');
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

  Future<void> _supprimerCompte() => FinDeSession.pendant(_menerSuppressionCompte);

  // Sous FinDeSession.pendant : un 401 du polling de l'espace (le compte vient
  // d'être supprimé) ne remplace pas le message de la suppression.
  Future<void> _menerSuppressionCompte() async {
    if (!await demanderConfirmationSuppression(context)) return;
    if (!mounted) return;
    setState(() => _suppressionEnCours = true);
    String messageFinal;
    try {
      await ApiService.supprimerMonCompte();
      messageFinal = 'Ton compte a été supprimé.';
    } on ApiException catch (e) {
      if (e.statusCode != 401) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message), // 409 : message serveur tel quel
          duration: const Duration(seconds: 8),
        ));
        return;
      }
      messageFinal = "Ta session n'est plus valide. Si tu venais de demander "
          'la suppression, elle a bien été prise en compte.';
    } catch (_) {
      // Réponse perdue ou trop lente, mais un 401 de la session est arrivé
      // entre-temps (FinDeSession) : le serveur a bien supprimé le compte.
      if (!FinDeSession.fermeeDuranteOperation) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossible de joindre Taama. Vérifie ta connexion et réessaie.'),
        ));
        return;
      }
      messageFinal = "Ta session n'est plus valide. Si tu venais de demander "
          'la suppression, elle a bien été prise en compte.';
    } finally {
      if (mounted) setState(() => _suppressionEnCours = false);
    }
    // Compte supprimé : la session de l'appareil est effacée, sans requête.
    await Deconnexion.effacerSessionLocale();
    if (!mounted) return;
    final messager = ScaffoldMessenger.of(context);
    // Retire aussi EcranEspaceChauffeur : son dispose() arrête le suivi GPS
    // et le heartbeat (le serveur a déjà passé est_en_ligne à False).
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const EcranConnexion()),
      (route) => false,
    );
    messager.showSnackBar(SnackBar(content: Text(messageFinal)));
  }

  /// « MOTO • Corola • AB 1234 MD » : libellé véhicule dédupliqué du
  /// serveur (Chauffeur.vehicule_libelle — jamais « corola Corola »), et
  /// aucun segment vide ni « null ».
  String _ligneVehicule(Map<String, dynamic> c) {
    String? texte(Object? v) {
      final t = v?.toString().trim() ?? '';
      return t.isEmpty || t == 'null' ? null : t;
    }

    final vehicule = texte(c['vehicule']) ??
        texte('${texte(c['marque']) ?? ''} ${texte(c['modele']) ?? ''}');
    return [texte(c['type_transport']), vehicule, texte(c['plaque'])]
        .whereType<String>()
        .join(' • ');
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
                                  _ligneVehicule(_chauffeur!),
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

                  // L'historique complet (détail, totaux du jour) vit dans
                  // « Mes courses », chargé page par page : plus tout
                  // l'historique à chaque ouverture du profil.
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      leading: const Icon(Icons.receipt_long_rounded, color: CouleursTaama.indigo),
                      title: const Text('Mes courses', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Courses faites et annulées, avec leur détail'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PageMesCourses()),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  // Volontairement discret, en fin de page : action
                  // irréversible, protégée par une saisie de confirmation.
                  Center(
                    child: TextButton.icon(
                      onPressed: _suppressionEnCours ? null : _supprimerCompte,
                      style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                      icon: _suppressionEnCours
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_forever_outlined),
                      label: const Text('Supprimer mon compte'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}