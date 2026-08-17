import 'package:flutter/material.dart';
import '../models/transport_option.dart';
import '../services/api_service.dart';
import 'espace_chauffeur_screen.dart';

/// Formulaire affiché une seule fois, à la toute première connexion d'un
/// conducteur — il crée lui-même son profil (plus besoin de passer par
/// l'admin Django).
class EcranInscriptionChauffeur extends StatefulWidget {
  const EcranInscriptionChauffeur({super.key});

  @override
  State<EcranInscriptionChauffeur> createState() => _EcranInscriptionChauffeurState();
}

class _EcranInscriptionChauffeurState extends State<EcranInscriptionChauffeur> {
  final _nomController = TextEditingController();
  final _marqueController = TextEditingController();
  final _modeleController = TextEditingController();
  final _plaqueController = TextEditingController();
  int? _typeSelectionne;
  // Sous-type véhicule (BERLINE/4X4/TRICYCLE), uniquement pertinent quand
  // _typeSelectionne == Voiture — pour Moto, déduit automatiquement
  // (MOTO), pas besoin de redemander.
  String? _sousTypeVoiture;
  String? _couleur;
  bool _enChargement = false;

  final List<TypeVehicule> _types = TypeVehicule.tous();

  // Correspond à Chauffeur.TYPE_VEHICULE_CHOICES (backend) pour le
  // sous-type "Voiture" — Moto n'a qu'une seule option (MOTO), pas besoin
  // de sélecteur séparé.
  static const List<(String valeur, String libelle, IconData icone)> _sousTypesVoiture = [
    ('BERLINE', 'Berline', Icons.directions_car),
    ('4X4', '4x4 / SUV', Icons.directions_car_filled),
    ('TRICYCLE', 'Tricycle', Icons.electric_rickshaw),
  ];

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

  bool get _estMoto => _typeSelectionne != null && _types[_typeSelectionne!].nom == 'Moto';

  @override
  void dispose() {
    _nomController.dispose();
    _marqueController.dispose();
    _modeleController.dispose();
    _plaqueController.dispose();
    super.dispose();
  }

  Future<void> _creerProfil() async {
    final nom = _nomController.text.trim();
    final marque = _marqueController.text.trim();
    final modele = _modeleController.text.trim();
    final plaque = _plaqueController.text.trim();

    final typeVehiculeManquant = _typeSelectionne != null && !_estMoto && _sousTypeVoiture == null;

    if (nom.isEmpty || marque.isEmpty || modele.isEmpty || plaque.isEmpty ||
        _typeSelectionne == null || _couleur == null || typeVehiculeManquant) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remplis tous les champs')),
      );
      return;
    }

    // Moto : un seul sous-type possible (MOTO), déduit — pas de choix
    // supplémentaire à faire porter au conducteur.
    final typeVehicule = _estMoto ? 'MOTO' : _sousTypeVoiture!;

    setState(() => _enChargement = true);
    try {
      await ApiService.creerMonProfilChauffeur(
        nom: nom,
        typeTransport: _types[_typeSelectionne!].nom,
        typeVehicule: typeVehicule,
        marque: marque,
        modele: modele,
        couleur: _couleur!,
        plaque: plaque,
      );

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const EcranEspaceChauffeur()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la création du profil')),
      );
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devenir conducteur'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Bienvenue ! Renseigne tes informations pour commencer à proposer des trajets.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nomController,
                decoration: const InputDecoration(
                  labelText: 'Ton nom complet',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Type de véhicule', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._types.asMap().entries.map((entry) {
                final index = entry.key;
                final type = entry.value;
                final selectionne = _typeSelectionne == index;

                return GestureDetector(
                  onTap: () => setState(() {
                    _typeSelectionne = index;
                    // Le sous-type ne s'applique qu'à Voiture — repartir de
                    // zéro si le conducteur change d'avis entre les deux.
                    _sousTypeVoiture = null;
                  }),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selectionne ? Colors.amber.withValues(alpha: 0.15) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectionne ? Colors.amber : Colors.grey.shade300,
                        width: selectionne ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(type.icone, color: Colors.black),
                        const SizedBox(width: 12),
                        Text(type.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
              }),
              // Sous-type (Berline/4x4/Tricycle) uniquement pour Voiture —
              // pour Moto, déduit automatiquement (un seul cas possible).
              if (_typeSelectionne != null && !_estMoto) ...[
                const SizedBox(height: 8),
                const Text('Précise le type', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _sousTypesVoiture.map((sousType) {
                    final (valeur, libelle, icone) = sousType;
                    final selectionne = _sousTypeVoiture == valeur;
                    return ChoiceChip(
                      label: Text(libelle),
                      avatar: Icon(icone, size: 18),
                      selected: selectionne,
                      selectedColor: Colors.amber.withValues(alpha: 0.3),
                      onSelected: (_) => setState(() => _sousTypeVoiture = valeur),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _marqueController,
                decoration: const InputDecoration(
                  labelText: 'Marque (ex: Toyota)',
                  prefixIcon: Icon(Icons.directions_car),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _modeleController,
                decoration: const InputDecoration(
                  labelText: 'Modèle (ex: Corolla)',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _couleur,
                decoration: const InputDecoration(
                  labelText: 'Couleur',
                  prefixIcon: Icon(Icons.palette_outlined),
                  border: OutlineInputBorder(),
                ),
                items: _couleurs.entries
                    .map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value)))
                    .toList(),
                onChanged: (valeur) => setState(() => _couleur = valeur),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _plaqueController,
                decoration: const InputDecoration(
                  labelText: 'Plaque d\'immatriculation',
                  prefixIcon: Icon(Icons.pin),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _enChargement ? null : _creerProfil,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _enChargement
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Créer mon profil', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
