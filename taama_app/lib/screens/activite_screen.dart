import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';

class EcranActivite extends StatefulWidget {
  const EcranActivite({super.key});

  @override
  State<EcranActivite> createState() => _EcranActiviteState();
}

class _EcranActiviteState extends State<EcranActivite>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _chargement = true;
  List<dynamic> _reservations = [];
  List<dynamic> _demandes = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _charger();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final res = await Future.wait([
        ApiService.mesReservations(),
        ApiService.mesDemandesClient(),
      ]);
      if (!mounted) return;
      setState(() {
        _reservations = res[0];
        _demandes = res[1];
      });
    } catch (e) {
      debugPrint('Erreur activite : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      appBar: AppBar(
        title: const Text('Activité',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: CouleursTaama.terreCuite,
          labelColor: CouleursTaama.indigo,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Réservations'),
            Tab(text: 'Demandes'),
          ],
        ),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(
              color: CouleursTaama.terreCuite))
          : RefreshIndicator(
              onRefresh: _charger,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildListeReservations(),
                  _buildListeDemandes(),
                ],
              ),
            ),
    );
  }

  Widget _buildListeReservations() {
    if (_reservations.isEmpty) {
      return const Center(child: Text('Aucune réservation'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reservations.length,
      itemBuilder: (context, index) {
        final r = _reservations[index] as Map<String, dynamic>;
        final trajet = r['trajet_propose'] as Map<String, dynamic>? ?? {};
        final statut = r['statut']?.toString() ?? '';
        return _CarteActivite(
          icone: Icons.event_seat,
          titre: '${trajet['depart'] ?? ''} → ${trajet['arrivee'] ?? ''}',
          sousTitre: '${trajet['prix_par_place'] ?? 0} FCFA',
          statut: _labelStatut(statut),
          couleurStatut: _couleurStatut(statut),
        );
      },
    );
  }

  Widget _buildListeDemandes() {
    if (_demandes.isEmpty) {
      return const Center(child: Text('Aucune demande'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _demandes.length,
      itemBuilder: (context, index) {
        final d = _demandes[index] as Map<String, dynamic>;
        final statut = d['statut']?.toString() ?? '';
        return _CarteActivite(
          icone: Icons.flash_on,
          titre: d['destination']?.toString() ?? '',
          sousTitre: '${d['prix_estime'] ?? 0} FCFA',
          statut: _labelStatut(statut),
          couleurStatut: _couleurStatut(statut),
        );
      },
    );
  }

  String _labelStatut(String statut) {
    return switch (statut) {
      'en_attente' => 'En attente',
      'confirmee' => 'Confirmée ✓',
      'annulee' => 'Annulée',
      'refusee' => 'Refusée',
      'en_route' => 'En route 🚗',
      'client_a_bord' => 'Vers destination 🚗',
      'termine' => 'Terminée ✓',
      'chauffeur_trouve' => 'Conducteur trouvé',
      'en_recherche' => 'En recherche...',
      'planifiee' => 'Planifiée 📅',
      _ => statut,
    };
  }

  Color _couleurStatut(String statut) {
    return switch (statut) {
      'confirmee' || 'termine' => Colors.green,
      'refusee' || 'annulee' => Colors.red,
      'en_route' || 'chauffeur_trouve' || 'client_a_bord' => Colors.blue,
      'en_recherche' || 'en_attente' => Colors.orange,
      'planifiee' => Colors.purple,
      _ => Colors.grey,
    };
  }
}

class _CarteActivite extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String sousTitre;
  final String statut;
  final Color couleurStatut;

  const _CarteActivite({
    required this.icone, required this.titre, required this.sousTitre,
    required this.statut, required this.couleurStatut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: couleurStatut, width: 4)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: couleurStatut.withValues(alpha: 0.12),
            child: Icon(icone, color: couleurStatut, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(sousTitre,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: couleurStatut.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(statut,
                style: TextStyle(
                    color: couleurStatut,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
