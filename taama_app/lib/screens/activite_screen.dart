import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/taama_theme.dart';
import '../utils/format.dart';

/// Activité du client (v4) : deux onglets, Réservations et Demandes.
/// Logique inchangée (chargement parallèle, mêmes appels API) ; habillage
/// TaamaColors/TaamaText, états vides soignés, lecture défensive.
class EcranActivite extends StatefulWidget {
  const EcranActivite({super.key});

  @override
  State<EcranActivite> createState() => _EcranActiviteState();
}

class _EcranActiviteState extends State<EcranActivite>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _chargement = true;
  List<Map<String, dynamic>> _reservations = const [];
  List<Map<String, dynamic>> _demandes = const [];

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
        _reservations = res[0].whereType<Map<String, dynamic>>().toList();
        _demandes = res[1].whereType<Map<String, dynamic>>().toList();
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Activite] Erreur : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TaamaColors.background,
      appBar: AppBar(
        title: const Text('Activité'),
        backgroundColor: TaamaColors.background,
        foregroundColor: TaamaColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: TaamaColors.primary,
          indicatorWeight: 3,
          labelColor: TaamaColors.primary,
          unselectedLabelColor: TaamaColors.textSecondary,
          labelStyle: TaamaText.body.copyWith(fontWeight: FontWeight.w800),
          unselectedLabelStyle: TaamaText.body.copyWith(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Réservations'),
            Tab(text: 'Demandes'),
          ],
        ),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: TaamaColors.primary))
          : RefreshIndicator(
              color: TaamaColors.primary,
              onRefresh: _charger,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _listeReservations(),
                  _listeDemandes(),
                ],
              ),
            ),
    );
  }

  Widget _listeReservations() {
    if (_reservations.isEmpty) {
      return _etatVide(Icons.event_seat_rounded, 'Aucune réservation');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reservations.length,
      itemBuilder: (context, index) {
        final r = _reservations[index];
        final trajet = r['trajet_propose'];
        final depart = trajet is Map ? trajet['depart']?.toString() ?? '' : '';
        final arrivee = trajet is Map ? trajet['arrivee']?.toString() ?? '' : '';
        final prix = trajet is Map ? (trajet['prix_par_place'] as num?)?.toInt() : null;
        final statut = r['statut']?.toString() ?? '';
        return _CarteActivite(
          icone: Icons.event_seat_rounded,
          titre: [depart, arrivee].where((s) => s.isNotEmpty).join(' → '),
          sousTitre: prix == null ? 'Réservation' : formaterFcfa(prix),
          statut: _labelStatut(statut),
          couleurStatut: _couleurStatut(statut),
        );
      },
    );
  }

  Widget _listeDemandes() {
    if (_demandes.isEmpty) {
      return _etatVide(Icons.local_taxi_rounded, 'Aucune course');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _demandes.length,
      itemBuilder: (context, index) {
        final d = _demandes[index];
        final statut = d['statut']?.toString() ?? '';
        final prix = (d['prix_estime'] as num?)?.toInt();
        return _CarteActivite(
          icone: Icons.local_taxi_rounded,
          titre: d['destination']?.toString() ?? 'Course',
          sousTitre: prix == null ? 'Course' : formaterFcfa(prix),
          statut: _labelStatut(statut),
          couleurStatut: _couleurStatut(statut),
        );
      },
    );
  }

  /// État vide scrollable, pour que le tirer-pour-rafraîchir fonctionne.
  Widget _etatVide(IconData icone, String texte) {
    return LayoutBuilder(
      builder: (context, contraintes) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: contraintes.maxHeight),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icone, size: 36, color: TaamaColors.textSecondary),
                const SizedBox(height: 12),
                Text(texte,
                    style: TaamaText.body.copyWith(
                        color: TaamaColors.textSecondary, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _labelStatut(String statut) => switch (statut) {
        'en_attente' => 'En attente',
        'confirmee' => 'Confirmée',
        'annulee' => 'Annulée',
        'refusee' => 'Refusée',
        'en_route' => 'En route',
        'client_a_bord' => 'Vers destination',
        'termine' => 'Terminée',
        'chauffeur_trouve' => 'Conducteur trouvé',
        'en_recherche' => 'Recherche…',
        'planifiee' => 'Planifiée',
        _ => statut,
      };

  Color _couleurStatut(String statut) => switch (statut) {
        'confirmee' || 'termine' => TaamaColors.success,
        'refusee' || 'annulee' => TaamaColors.danger,
        'en_route' || 'chauffeur_trouve' || 'client_a_bord' => TaamaColors.primary,
        'en_recherche' || 'en_attente' => TaamaColors.star,
        'planifiee' => TaamaColors.navy,
        _ => TaamaColors.textSecondary,
      };
}

class _CarteActivite extends StatelessWidget {
  const _CarteActivite({
    required this.icone,
    required this.titre,
    required this.sousTitre,
    required this.statut,
    required this.couleurStatut,
  });

  final IconData icone;
  final String titre;
  final String sousTitre;
  final String statut;
  final Color couleurStatut;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.md),
        boxShadow: TaamaShadows.card,
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: couleurStatut.withValues(alpha: 0.14),
            child: Icon(icone, color: couleurStatut, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre.isEmpty ? '—' : titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TaamaText.body.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  sousTitre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TaamaText.body.copyWith(
                      color: TaamaColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: couleurStatut.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(TaamaRadius.pill),
            ),
            child: Text(
              statut,
              style: TextStyle(
                color: couleurStatut,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
