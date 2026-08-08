import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'recharge_screen.dart';

/// Écran de portefeuille, utilisable aussi bien côté client que conducteur.
/// - Le client y voit ses recharges + ses paiements effectués.
/// - Le conducteur y voit ses recharges + les paiements reçus (gains).
class EcranPortefeuille extends StatefulWidget {
  /// true si affiché côté conducteur (pour montrer les gains reçus en plus
  /// des recharges), false côté client (montre les paiements effectués).
  final bool estChauffeur;

  const EcranPortefeuille({super.key, required this.estChauffeur});

  @override
  State<EcranPortefeuille> createState() => _EcranPortefeuilleState();
}

class _EcranPortefeuilleState extends State<EcranPortefeuille> {
  bool _chargement = true;
  int _solde = 0;
  List<Map<String, dynamic>> _historique = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final solde = await ApiService.monSolde();
      final recharges = await ApiService.mesRecharges();
      final transactions = widget.estChauffeur
          ? await ApiService.mesTransactions()
          : await ApiService.mesPaiementsClient();

      final combine = <Map<String, dynamic>>[
        ...recharges.map((r) => {...r as Map<String, dynamic>, '_type': 'recharge'}),
        ...transactions.map((t) => {...t as Map<String, dynamic>, '_type': 'transaction'}),
      ];
      combine.sort((a, b) {
        final dateA = DateTime.tryParse(a['cree_le'] ?? '') ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['cree_le'] ?? '') ?? DateTime(2000);
        return dateB.compareTo(dateA);
      });

      if (!mounted) return;
      setState(() {
        _solde = solde;
        _historique = combine;
      });
    } catch (e) {
      debugPrint('Erreur chargement portefeuille : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _ouvrirRecharge() async {
    final nouveauSolde = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EcranRecharge()),
    );
    if (nouveauSolde != null) await _charger();
  }

  (IconData, String, String, Color) _infosEntree(Map<String, dynamic> entree) {
    if (entree['_type'] == 'recharge') {
      final libelles = {'orange': 'Orange Money', 'moov': 'Moov Money', 'wave': 'Wave'};
      return (
        Icons.add_circle,
        '+${entree['montant']} FCFA',
        'Recharge • ${libelles[entree['operateur']] ?? entree['operateur']}',
        Colors.blue,
      );
    } else {
      // Transaction : pour le conducteur c'est un gain reçu, pour le client une dépense
      if (widget.estChauffeur) {
        return (
          Icons.check_circle,
          '+${entree['montant_chauffeur']} FCFA',
          'Course • Total ${entree['montant_total']} FCFA (commission ${entree['commission']} FCFA)',
          Colors.green,
        );
      } else {
        return (
          Icons.remove_circle,
          '-${entree['montant_total']} FCFA',
          'Paiement de course',
          Colors.red,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mon portefeuille'),
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Solde Taama', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 8),
                        Text(
                          '$_solde FCFA',
                          style: const TextStyle(color: Colors.amber, fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _ouvrirRecharge,
                            icon: const Icon(Icons.add),
                            label: const Text('Recharger'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text('Historique', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  if (_historique.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text('Aucune activité pour l\'instant.', style: TextStyle(color: Colors.grey.shade500)),
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
                                  Text(titre, style: TextStyle(fontWeight: FontWeight.bold, color: couleur)),
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