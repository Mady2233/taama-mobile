import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';
import '../widgets/widget_notation.dart';
import '../widgets/widget_sos.dart';
import '../widgets/widget_annulation.dart';
import 'chat_screen.dart';

/// Affiche toutes les réservations faites par le passager connecté,
/// avec leur statut actuel, le paiement depuis le solde Taama, et la
/// possibilité d'annuler celles encore actives.
class EcranMesReservations extends StatefulWidget {
  const EcranMesReservations({super.key});

  @override
  State<EcranMesReservations> createState() => _EcranMesReservationsState();
}

class _EcranMesReservationsState extends State<EcranMesReservations> {
  bool _chargement = true;
  List<dynamic> _reservations = [];
  int? _enAnnulation;
  int? _enPaiement;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final reservations = await ApiService.mesReservations();
      if (!mounted) return;
      setState(() => _reservations = reservations);
    } catch (e) {
      debugPrint('Erreur chargement réservations : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _annuler(int reservationId, DateTime dateCreation) async {
    final resultat = await afficherDialogueAnnulation(
      context,
      dateCreation: dateCreation,
      estChauffeur: false,
    );
    if (resultat == null) return;

    setState(() => _enAnnulation = reservationId);
    try {
      final reponse = await ApiService.annulerReservation(
        reservationId,
        motif: resultat['motif'] as String,
      );
      if (!mounted) return;

      final penalite = reponse['penalite'] as int? ?? 0;
      if (penalite > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Réservation annulée. Pénalité : $penalite FCFA'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      await _charger();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _enAnnulation = null);
    }
  }

  Future<void> _payer(int reservationId) async {
    setState(() => _enPaiement = reservationId);
    try {
      await ApiService.payerReservation(reservationId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paiement effectué depuis ton solde Taama')),
      );
      await _charger();
      if (!mounted) return;
      // Le paiement vient de réussir : la réservation n'a donc pas encore été notée
      await _proposerNotation(reservationId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _enPaiement = null);
    }
  }

  Future<void> _proposerNotation(int reservationId) async {
    await afficherDialogueNotation(
      context: context,
      onEnvoyer: (note, commentaire) async {
        await ApiService.noterChauffeurReservation(reservationId, note, commentaire);
        if (mounted) await _charger();
      },
    );
  }

  (Color, String) _infosStatut(String statut) {
    switch (statut) {
      case 'en_attente':
        return (Colors.orange, 'En attente de confirmation');
      case 'confirmee':
        return (Colors.green, 'Confirmée');
      case 'refusee':
        return (Colors.red, 'Refusée par le conducteur');
      case 'annulee':
        return (Colors.grey, 'Annulée');
      default:
        return (Colors.grey, statut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Mes réservations'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: CouleursTaama.terreCuite))
          : RefreshIndicator(
              onRefresh: _charger,
              child: _reservations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          'Tu n\'as pas encore réservé de trajet.',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _reservations.length,
                      itemBuilder: (context, index) {
                        final reservation = _reservations[index];
                        final trajet = reservation['trajet_propose'];
                        final conducteur = trajet['conducteur'];
                        final statut = reservation['statut']?.toString() ?? '';
                        final paye = reservation['paye'] as bool? ?? false;
                        final (couleur, libelle) = _infosStatut(statut);
                        final estActive = statut == 'en_attente' || statut == 'confirmee';
                        final peutPayer = statut == 'confirmee' && !paye;
                        final dejaNote = reservation['deja_note'] as bool? ?? false;
                        final peutNoter = paye && !dejaNote && (statut == 'confirmee' || statut == 'termine');
                        final estVoiture = conducteur['type_transport'] == 'Voiture';
                        final dateCreation = DateTime.tryParse(reservation['cree_le']?.toString() ?? '') ?? DateTime.now();

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
                                          '${trajet['depart']} → ${trajet['arrivee']}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${conducteur['nom']} • Départ ${trajet['heure_depart']}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '${trajet['prix_par_place']} FCFA',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (statut == 'confirmee') ...[
                                    const SizedBox(width: 8),
                                    BoutonSOS(reservationId: reservation['id'] as int),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: couleur.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      libelle,
                                      style: TextStyle(color: couleur, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                  if (paye) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        '✓ Payé',
                                        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                              // Bouton de paiement, uniquement si confirmée et pas encore payée
                              if (peutPayer) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _enPaiement == reservation['id']
                                        ? null
                                        : () => _payer(reservation['id'] as int),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: _enPaiement == reservation['id']
                                        ? const SizedBox(
                                            width: 18, height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : Text('Payer ${trajet['prix_par_place']} FCFA'),
                                  ),
                                ),
                              ],

                              // Bouton de messagerie, uniquement si la réservation est confirmée
                              if (statut == 'confirmee') ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EcranChat(
                                          roomName: 'reservation_${reservation['id']}',
                                          titreConversation: conducteur['nom'],
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.chat_bubble_outline, color: CouleursTaama.indigo),
                                    label: const Text('Envoyer un message'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: CouleursTaama.indigo,
                                      side: const BorderSide(color: CouleursTaama.indigo),
                                    ),
                                  ),
                                ),
                              ],

                              // Bouton de notation, uniquement si payée et pas encore notée
                              if (peutNoter) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _proposerNotation(reservation['id'] as int),
                                    icon: const Icon(Icons.star_border, color: CouleursTaama.or),
                                    label: const Text('Noter le conducteur'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: CouleursTaama.or,
                                      side: const BorderSide(color: CouleursTaama.or),
                                    ),
                                  ),
                                ),
                              ],

                              if (estActive) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: _enAnnulation == reservation['id']
                                        ? null
                                        : () => _annuler(reservation['id'] as int, dateCreation),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                    ),
                                    child: _enAnnulation == reservation['id']
                                        ? const SizedBox(
                                            width: 18, height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                                          )
                                        : const Text('Annuler la réservation'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}