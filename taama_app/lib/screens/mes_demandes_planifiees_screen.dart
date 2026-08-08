import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';

/// Liste les demandes instantanées planifiées à l'avance par le client,
/// avec la possibilité de les annuler avant leur activation automatique.
class MesDemandesPlanifieesScreen extends StatefulWidget {
  const MesDemandesPlanifieesScreen({super.key});

  @override
  State<MesDemandesPlanifieesScreen> createState() => _MesDemandesPlanifieesScreenState();
}

class _MesDemandesPlanifieesScreenState extends State<MesDemandesPlanifieesScreen> {
  bool _chargement = true;
  List<dynamic> _demandes = [];
  int? _enAnnulation;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final demandes = await ApiService.mesDemandesPlanifiees();
      if (!mounted) return;
      setState(() => _demandes = demandes);
    } catch (e) {
      debugPrint('Erreur chargement demandes planifiées : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _annuler(int demandeId) async {
    setState(() => _enAnnulation = demandeId);
    try {
      await ApiService.annulerDemande(demandeId);
      await _charger();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de l\'annulation')),
      );
    } finally {
      if (mounted) setState(() => _enAnnulation = null);
    }
  }

  String _formaterDateHeure(String? isoString) {
    if (isoString == null) return '';
    final date = DateTime.tryParse(isoString);
    if (date == null) return '';
    final local = date.toLocal();
    final jour = local.day.toString().padLeft(2, '0');
    final mois = local.month.toString().padLeft(2, '0');
    final heure = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$jour/$mois/${local.year} à $heure:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Courses planifiées'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _charger,
        child: _chargement
            ? const Center(child: CircularProgressIndicator(color: CouleursTaama.indigo))
            : _demandes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(
                        'Tu n\'as pas encore de course planifiée.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _demandes.length,
                    itemBuilder: (context, index) {
                      final demande = _demandes[index] as Map<String, dynamic>;
                      final demandeId = demande['id'] is int
                          ? demande['id'] as int
                          : int.tryParse(demande['id'].toString()) ?? 0;
                      final destination = demande['destination']?.toString() ?? '';
                      final typeTransport = demande['type_transport']?.toString() ?? 'Voiture';
                      final prixEstime = demande['prix_estime']?.toString() ?? '';
                      final dateHeure = _formaterDateHeure(demande['date_heure_planifiee']?.toString());
                      final estVoiture = typeTransport == 'Voiture';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: CouleursTaama.indigo,
                                  radius: 20,
                                  child: Icon(
                                    estVoiture ? Icons.directions_car : Icons.two_wheeler,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        destination,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      Text(
                                        typeTransport,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),
                                if (prixEstime.isNotEmpty)
                                  Text(
                                    '$prixEstime FCFA',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: CouleursTaama.indigo.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.schedule, size: 14, color: CouleursTaama.indigo),
                                  const SizedBox(width: 6),
                                  Text(
                                    dateHeure,
                                    style: const TextStyle(color: CouleursTaama.indigo, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _enAnnulation == demandeId ? null : () => _annuler(demandeId),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                ),
                                child: _enAnnulation == demandeId
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                                      )
                                    : const Text('Annuler'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
