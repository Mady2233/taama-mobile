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
  final _vehiculeController = TextEditingController();
  final _plaqueController = TextEditingController();
  int? _typeSelectionne;
  bool _enChargement = false;

  final List<TypeVehicule> _types = TypeVehicule.tous();

  @override
  void dispose() {
    _nomController.dispose();
    _vehiculeController.dispose();
    _plaqueController.dispose();
    super.dispose();
  }

  Future<void> _creerProfil() async {
    final nom = _nomController.text.trim();
    final vehicule = _vehiculeController.text.trim();
    final plaque = _plaqueController.text.trim();

    if (nom.isEmpty || vehicule.isEmpty || plaque.isEmpty || _typeSelectionne == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remplis tous les champs')),
      );
      return;
    }

    setState(() => _enChargement = true);
    try {
      await ApiService.creerMonProfilChauffeur(
        nom: nom,
        typeTransport: _types[_typeSelectionne!].nom,
        vehicule: vehicule,
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
                  onTap: () => setState(() => _typeSelectionne = index),
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
              const SizedBox(height: 8),
              TextField(
                controller: _vehiculeController,
                decoration: const InputDecoration(
                  labelText: 'Modèle du véhicule (ex: Toyota Corolla grise)',
                  prefixIcon: Icon(Icons.directions_car),
                  border: OutlineInputBorder(),
                ),
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