import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Écran de profil : affiche le téléphone (lecture seule), permet de
/// modifier le nom, et montre l'historique combiné des réservations et
/// des demandes instantanées, trié du plus récent au plus ancien.
class EcranProfil extends StatefulWidget {
  const EcranProfil({super.key});

  @override
  State<EcranProfil> createState() => _EcranProfilState();
}

class _EcranProfilState extends State<EcranProfil> {
  bool _chargement = true;
  Map<String, dynamic>? _profil;
  List<Map<String, dynamic>> _historique = [];

  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _nomController = TextEditingController();
  bool _modeEdition = false;
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _prenomController.dispose();
    _nomController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final profil = await ApiService.monProfil();
      final reservations = await ApiService.mesReservations();
      final demandes = await ApiService.mesDemandesClient();

      // Je fusionne les deux historiques en ajoutant un champ "type" pour
      // savoir comment afficher chaque entrée, puis je trie par date
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
        _profil = profil;
        _historique = combine;
        _prenomController.text = profil['first_name'] ?? '';
        _nomController.text = profil['last_name'] ?? '';
      });
    } catch (e) {
      debugPrint('Erreur chargement profil : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _enregistrerProfil() async {
    setState(() => _enregistrement = true);
    try {
      final profil = await ApiService.modifierProfil(
        prenom: _prenomController.text.trim(),
        nom: _nomController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _profil = profil;
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

  /// Construit le texte et l'icône d'affichage pour une entrée d'historique
  (IconData, String, String, Color) _infosEntree(Map<String, dynamic> entree) {
    if (entree['_type'] == 'reservation') {
      final trajet = entree['trajet_propose'];
      final statut = entree['statut'] as String? ?? '';
      final couleur = switch (statut) {
        'confirmee' => Colors.green,
        'refusee' => Colors.red,
        'annulee' => Colors.grey,
        _ => Colors.orange,
      };
      return (
        Icons.event_seat,
        '${trajet['depart']} → ${trajet['arrivee']}',
        'Réservation • ${trajet['prix_par_place']} FCFA',
        couleur,
      );
    } else {
      final statut = entree['statut'] as String? ?? '';
      final couleur = switch (statut) {
        'termine' => Colors.green,
        'annule' => Colors.grey,
        'en_route' => Colors.blue,
        _ => Colors.orange,
      };
      return (
        Icons.flash_on,
        entree['destination'] as String? ?? 'Destination inconnue',
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
        title: const Text('Mon profil'),
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
                            const CircleAvatar(
                              radius: 32,
                              backgroundColor: Colors.amber,
                              child: Icon(Icons.person, color: Colors.black, size: 32),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _profil?['telephone'] ?? '',
                                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    (_profil?['first_name']?.toString().isNotEmpty == true ||
                                            _profil?['last_name']?.toString().isNotEmpty == true)
                                        ? '${_profil?['first_name'] ?? ''} ${_profil?['last_name'] ?? ''}'.trim()
                                        : 'Nom non renseigné',
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
                            decoration: const InputDecoration(
                              labelText: 'Prénom',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _nomController,
                            decoration: const InputDecoration(
                              labelText: 'Nom',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _enregistrement ? null : _enregistrerProfil,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black,
                            ),
                            child: _enregistrement
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                  )
                                : const Text('Enregistrer'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text('Historique', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  if (_historique.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Aucun trajet pour l\'instant.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
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