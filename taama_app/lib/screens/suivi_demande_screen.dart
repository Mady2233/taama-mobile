import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../screens/chat_screen.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/couleurs_taama.dart';
import '../widgets/widget_notation.dart';
import '../widgets/widget_sos.dart';
import '../widgets/widget_annulation.dart';

/// Suivi d'une demande instantanée : interroge le backend toutes les 3
/// secondes pour connaître l'évolution (recherche → conducteur trouvé → en route).
class EcranSuiviDemande extends StatefulWidget {
  final int demandeId;
  final String destination;
  final String typeTransport;

  const EcranSuiviDemande({
    super.key,
    required this.demandeId,
    required this.destination,
    required this.typeTransport,
  });

  @override
  State<EcranSuiviDemande> createState() => _EcranSuiviDemandeState();
}

class _EcranSuiviDemandeState extends State<EcranSuiviDemande> {
  String _statut = 'en_recherche';
  Map<String, dynamic>? _chauffeur;
  int? _prixEstime;
  bool _paye = false;
  bool _dejaNote = false;
  Timer? _timerPolling;
  bool _enAnnulation = false;
  bool _enPaiement = false;
  DateTime _dateCreation = DateTime.now();

  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();
  LatLng? _positionConducteur;
  bool _suiviPositionDemarre = false;

  @override
  void initState() {
    super.initState();
    _rafraichir();
    _timerPolling = Timer.periodic(const Duration(seconds: 3), (_) => _rafraichir());
  }

  @override
  void dispose() {
    _timerPolling?.cancel();
    _locationService.arreter();
    super.dispose();
  }

  Future<void> _rafraichir() async {
    try {
      final demande = await ApiService.detailDemande(widget.demandeId);
      if (!mounted) return;
      setState(() {
        _statut = demande['statut']?.toString() ?? '';
        _chauffeur = demande['chauffeur'] as Map<String, dynamic>?;
        final prixRaw = demande['prix_estime'];
        _prixEstime = prixRaw is int ? prixRaw : int.tryParse(prixRaw?.toString() ?? '');
        _paye = demande['paye'] as bool? ?? false;
        _dejaNote = demande['deja_note'] as bool? ?? false;
        if (demande['cree_le'] != null) {
          _dateCreation = DateTime.tryParse(demande['cree_le'].toString()) ?? _dateCreation;
        }
      });
      if (_statut == 'termine' || _statut == 'annule') {
        _timerPolling?.cancel();
      }
      if (_statut == 'en_route') {
        _demarrerSuiviPosition();
      } else if (_suiviPositionDemarre) {
        _locationService.arreter();
        _suiviPositionDemarre = false;
        _positionConducteur = null;
      }
    } catch (e) {
      debugPrint('Erreur rafraîchissement demande : $e');
    }
  }

  /// Connecte le WebSocket de localisation dès que le conducteur est en
  /// route, pour faire bouger le marqueur sur la mini-carte en temps réel.
  void _demarrerSuiviPosition() {
    if (_suiviPositionDemarre) return;
    _suiviPositionDemarre = true;

    _locationService.ecouterPosition('${widget.demandeId}', (lat, lng) {
      if (!mounted) return;
      setState(() => _positionConducteur = LatLng(lat, lng));
    });
  }

  Future<void> _annuler() async {
    final resultat = await afficherDialogueAnnulation(
      context,
      dateCreation: _dateCreation,
      estChauffeur: false,
    );
    if (resultat == null) return;

    setState(() => _enAnnulation = true);
    try {
      final reponse = await ApiService.annulerDemande(
        widget.demandeId,
        motif: resultat['motif'] as String,
      );

      _timerPolling?.cancel();
      if (!mounted) return;

      // Affiche la pénalité appliquée
      final penalite = reponse['penalite'] as int? ?? 0;
      if (penalite > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Course annulée. Pénalité : $penalite FCFA'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _enAnnulation = false);
    }
  }

  Future<void> _payer() async {
    setState(() => _enPaiement = true);
    try {
      await ApiService.payerDemande(widget.demandeId);
      if (!mounted) return;
      setState(() => _paye = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paiement effectué, merci !')),
      );
      // Le paiement vient de réussir : la demande n'a donc pas encore été notée
      await _proposerNotation();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors du paiement')),
      );
    } finally {
      if (mounted) setState(() => _enPaiement = false);
    }
  }

  Future<void> _proposerNotation() async {
    await afficherDialogueNotation(
      context: context,
      onEnvoyer: (note, commentaire) async {
        await ApiService.noterChauffeurDemande(widget.demandeId, note, commentaire);
        if (mounted) setState(() => _dejaNote = true);
      },
    );
  }

  /// `ChauffeurSerializer` n'expose plus de champ `vehicule` unique (marque
  /// + modèle structurés depuis le backend) : je recompose l'affichage ici.
  String _vehiculeLibelle() {
    final marque = _chauffeur?['marque']?.toString() ?? '';
    final modele = _chauffeur?['modele']?.toString() ?? '';
    return '$marque $modele'.trim();
  }

  String get _texteStatut {
    switch (_statut) {
      case 'en_recherche':
        return 'Recherche d\'un conducteur (${widget.typeTransport.toLowerCase()})...';
      case 'chauffeur_trouve':
        return 'Conducteur trouvé !';
      case 'en_route':
        return 'En route vers votre destination';
      case 'termine':
        return 'Trajet terminé';
      case 'annule':
        return 'Trajet annulé';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final estEnRecherche = _statut == 'en_recherche';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Suivi de la demande'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: BoutonSOS(demandeId: widget.demandeId),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.amber),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.destination,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          Text(
                            'Mode : ${widget.typeTransport}'
                            '${_prixEstime != null ? ' • $_prixEstime FCFA' : ''}',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Center(
                child: Column(
                  children: [
                    if (estEnRecherche)
                      const SizedBox(
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 5),
                      )
                    else
                      Icon(
                        _statut == 'chauffeur_trouve' ? Icons.check_circle : Icons.directions_car,
                        color: Colors.amber,
                        size: 64,
                      ),
                    const SizedBox(height: 20),
                    Text(_texteStatut,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              if (_chauffeur != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.black,
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_chauffeur?['nom']?.toString() ?? 'Conducteur',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(
                              '${_vehiculeLibelle()} • ${_chauffeur?['plaque']?.toString() ?? ''}',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 18),
                          const SizedBox(width: 4),
                          Text(_chauffeur?['note']?.toString() ?? '5.0', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_positionConducteur != null) ...[
                const SizedBox(height: 16),
                _MiniCarteConducteur(mapController: _mapController, position: _positionConducteur),
              ],
              const SizedBox(height: 40),
              // Bouton de chat, visible dès qu'un conducteur est assigné
              if (_chauffeur != null && _statut != 'annule') ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EcranChat(
                          roomName: 'demande_${widget.demandeId}',
                          titreConversation: _chauffeur?['nom']?.toString() ?? 'Conducteur',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Envoyer un message'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CouleursTaama.indigo,
                    side: const BorderSide(color: CouleursTaama.indigo),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
              if ((_statut == 'en_route' || _statut == 'termine') && !_paye) ...[
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _enPaiement ? null : _payer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _enPaiement
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Payer $_prixEstime FCFA', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 12),
              ],
              if (_paye)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('✓ Payé', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                ),
              // Bouton de notation, uniquement si payée et pas encore notée
              if (_paye && !_dejaNote && (_statut == 'en_route' || _statut == 'termine')) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _proposerNotation,
                  icon: const Icon(Icons.star_border, color: CouleursTaama.or),
                  label: const Text('Noter le conducteur'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CouleursTaama.or,
                    side: const BorderSide(color: CouleursTaama.or),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
              if (_statut != 'termine' && _statut != 'annule') ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _enAnnulation ? null : _annuler,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _enAnnulation
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                        )
                      : const Text('Annuler la demande', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini-carte affichée pendant que le conducteur est en route : montre sa
/// position en temps réel (reçue via [LocationService]) sous forme de
/// marqueur, qui se déplace au fur et à mesure des mises à jour.
class _MiniCarteConducteur extends StatelessWidget {
  final MapController mapController;
  final LatLng? position;

  // Centre par défaut (Bamako), utilisé tant qu'aucune position n'est reçue
  static const LatLng _centreParDefaut = LatLng(12.6392, -8.0029);

  const _MiniCarteConducteur({required this.mapController, required this.position});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 180,
        child: Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: position ?? _centreParDefaut,
                initialZoom: 15.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.taama.app',
                ),
                if (position != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: position!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.directions_car, color: CouleursTaama.terreCuite, size: 32),
                      ),
                    ],
                  ),
              ],
            ),
            if (position == null)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: Text(
                    'En attente de la position du conducteur...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}