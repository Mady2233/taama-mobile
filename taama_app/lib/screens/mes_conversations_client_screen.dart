import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';
import 'chat_screen.dart';

/// Liste toutes les conversations actives du client : une entrée par
/// réservation confirmée et par demande instantanée en cours (conducteur
/// trouvé ou en route). Chaque entrée ouvre le chat correspondant.
class MesConversationsClientScreen extends StatefulWidget {
  const MesConversationsClientScreen({super.key});

  @override
  State<MesConversationsClientScreen> createState() => _MesConversationsClientScreenState();
}

class _MesConversationsClientScreenState extends State<MesConversationsClientScreen> {
  bool _chargement = true;
  List<dynamic> _reservations = [];
  List<dynamic> _demandes = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final reservations = await ApiService.mesReservations();
      final demandes = await ApiService.mesDemandesClient();
      if (!mounted) return;
      setState(() {
        _reservations = reservations.where((r) => r['statut'] == 'confirmee').toList();
        _demandes = demandes
            .where((d) =>
                d['statut'] == 'chauffeur_trouve' ||
                d['statut'] == 'en_route' ||
                d['statut'] == 'client_a_bord')
            .toList();
      });
    } catch (e) {
      debugPrint('Erreur chargement conversations : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  String _libelleStatutDemande(String statut) {
    switch (statut) {
      case 'chauffeur_trouve':
        return 'Conducteur trouvé';
      case 'en_route':
        return 'En route';
      case 'client_a_bord':
        return 'Vers votre destination';
      default:
        return statut;
    }
  }

  void _ouvrirChat({required String roomName, required String titre}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EcranChat(roomName: roomName, titreConversation: titre),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _reservations.length + _demandes.length;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mes messages'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: CouleursTaama.terreCuite))
          : RefreshIndicator(
              onRefresh: _charger,
              child: total == 0
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              'Aucune conversation active.',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: total,
                      itemBuilder: (context, index) {
                        if (index < _reservations.length) {
                          final reservation = _reservations[index];
                          final trajet = reservation['trajet_propose'];
                          final conducteur = trajet['conducteur'];
                          return _BulleConversation(
                            titre: '${trajet['depart']} → ${trajet['arrivee']}',
                            sousTitre: '${conducteur['nom']} • Confirmée',
                            onTap: () => _ouvrirChat(
                              roomName: 'reservation_${reservation['id']}',
                              titre: conducteur['nom'] as String? ?? 'Conducteur',
                            ),
                          );
                        }

                        final demande = _demandes[index - _reservations.length];
                        final conducteur = demande['chauffeur'];
                        final nomConducteur = conducteur?['nom'] as String? ?? 'Conducteur';
                        return _BulleConversation(
                          titre: demande['destination'] as String? ?? 'Destination inconnue',
                          sousTitre: '$nomConducteur • ${_libelleStatutDemande(demande['statut'] as String? ?? '')}',
                          onTap: () => _ouvrirChat(
                            roomName: 'demande_${demande['id']}',
                            titre: demande['destination'] as String? ?? 'Destination inconnue',
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// Une conversation dans la liste : icône de chat, trajet/destination et
/// sous-titre (nom du conducteur + statut).
class _BulleConversation extends StatelessWidget {
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  const _BulleConversation({
    required this.titre,
    required this.sousTitre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: CouleursTaama.indigo,
          radius: 22,
          child: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
        ),
        title: Text(titre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          sousTitre,
          style: const TextStyle(color: CouleursTaama.terreCuite, fontWeight: FontWeight.bold, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
