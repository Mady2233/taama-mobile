import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';
import 'chat_screen.dart';

/// Liste toutes les conversations actives du conducteur : une entrée par
/// demande instantanée qui lui est assignée. Chaque entrée ouvre le chat
/// correspondant.
class MesConversationsScreen extends StatefulWidget {
  const MesConversationsScreen({super.key});

  @override
  State<MesConversationsScreen> createState() => _MesConversationsScreenState();
}

class _MesConversationsScreenState extends State<MesConversationsScreen> {
  bool _chargement = true;
  List<dynamic> _demandes = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final demandes = await ApiService.mesDemandesAssignees();
      if (!mounted) return;
      setState(() => _demandes = demandes);
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
        return 'Client à bord';
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mes conversations'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: CouleursTaama.terreCuite))
          : RefreshIndicator(
              onRefresh: _charger,
              child: _demandes.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(
                            child: Text(
                              'Aucune conversation active pour le moment.',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _demandes.length,
                      itemBuilder: (context, index) {
                        final demande = _demandes[index];
                        return _BulleConversation(
                          titre: demande['destination'] as String? ?? 'Destination inconnue',
                          statut: _libelleStatutDemande(demande['statut'] as String? ?? ''),
                          onTap: () => _ouvrirChat(
                            roomName: 'demande_${demande['id']}',
                            titre: 'Client - ${demande['destination']}',
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// Une conversation dans la liste : icône de chat, nom de la course et statut.
class _BulleConversation extends StatelessWidget {
  final String titre;
  final String statut;
  final VoidCallback onTap;

  const _BulleConversation({
    required this.titre,
    required this.statut,
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
          child: const Icon(Icons.chat_bubble, color: Colors.white, size: 20),
        ),
        title: Text(titre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: CouleursTaama.terreCuite.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statut,
              style: const TextStyle(color: CouleursTaama.terreCuite, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
