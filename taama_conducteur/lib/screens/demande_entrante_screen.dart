import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';
import 'navigation_screen.dart';

/// Vitesse moyenne d'approche en ville (Bamako) — même hypothèse que le
/// backend (VITESSE_APPROCHE_KMH dans trajets/views.py) pour rester cohérent
/// avec l'ETA affichée côté client sur l'écran de sélection de véhicule.
const double _vitesseApprocheKmh = 20;

/// Écran plein écran affiché dès qu'une nouvelle demande instantanée est
/// attribuée au conducteur (statut 'chauffeur_trouve') — déclenché soit par
/// le polling de l'espace chauffeur (app au premier plan), soit par un tap
/// sur la notification FCM (voir DemandeEntranteNavigator).
///
/// Le compte à rebours de 30s est PUREMENT VISUEL : à zéro, on ferme l'écran
/// et on tente un refus en best-effort (l'app est forcément au premier plan
/// puisque ce timer tourne). Le VRAI timeout — réassignation même si l'app
/// est tuée — est côté serveur (Lot 3) ; cet écran ne le garantit pas.
class EcranDemandeEntrante extends StatefulWidget {
  final int demandeId;
  final Map<String, dynamic>? demandeInitiale;

  const EcranDemandeEntrante({
    super.key,
    required this.demandeId,
    this.demandeInitiale,
  });

  @override
  State<EcranDemandeEntrante> createState() => _EcranDemandeEntranteState();
}

class _EcranDemandeEntranteState extends State<EcranDemandeEntrante> {
  static const int _dureeCompteARebours = 30;

  Map<String, dynamic>? _demande;
  bool _chargement = true;
  bool _demandeIntrouvable = false;
  // Anti double-tap : dès le premier appui (Accepter OU Ignorer), les DEUX
  // boutons sont désactivés — jamais deux POST accepter/refuser en parallèle.
  bool _enTraitement = false;
  int _secondesRestantes = _dureeCompteARebours;
  Timer? _timerCompteARebours;

  LatLng? _positionActuelle;
  int? _etaMinutes;

  @override
  void initState() {
    super.initState();
    _demande = widget.demandeInitiale;
    _verifierEtDemarrer();
  }

  @override
  void dispose() {
    _timerCompteARebours?.cancel();
    super.dispose();
  }

  /// Revérifie que la demande est TOUJOURS 'chauffeur_trouve' et assignée à
  /// ce conducteur avant d'afficher quoi que ce soit — évite un écran
  /// fantôme si elle a déjà été résolue/réattribuée pendant que l'app était
  /// en arrière-plan (ou avant même la 1ère frame, ex. tap sur une
  /// notification obsolète). Utilise mesDemandesAssignees (pas
  /// detail_demande, qui est réservé au CLIENT côté backend).
  Future<void> _verifierEtDemarrer() async {
    try {
      final demandes = await ApiService.mesDemandesAssignees();
      final actuelle = demandes.cast<Map<String, dynamic>>().where(
            (d) => d['id'] == widget.demandeId && d['statut'] == 'chauffeur_trouve',
          );
      if (!mounted) return;

      if (actuelle.isEmpty) {
        setState(() {
          _demandeIntrouvable = true;
          _chargement = false;
        });
        return;
      }

      setState(() {
        _demande = actuelle.first;
        _chargement = false;
      });
      _demarrerCompteARebours();
      _calculerPositionEtEta();
    } catch (e) {
      debugPrint('[DemandeEntrante] Erreur vérification statut : $e');
      if (!mounted) return;
      // Pas de vérification réseau possible : on affiche quand même avec les
      // données déjà connues plutôt que de bloquer le conducteur — la vraie
      // garde anti-double-accept reste de toute façon côté serveur
      // (select_for_update dans accepter_demande).
      if (_demande != null) {
        setState(() => _chargement = false);
        _demarrerCompteARebours();
        _calculerPositionEtEta();
      } else {
        setState(() {
          _demandeIntrouvable = true;
          _chargement = false;
        });
      }
    }
  }

  void _demarrerCompteARebours() {
    _timerCompteARebours?.cancel();
    _secondesRestantes = _dureeCompteARebours;
    _timerCompteARebours = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondesRestantes <= 1) {
        timer.cancel();
        _expirer();
        return;
      }
      setState(() => _secondesRestantes--);
    });
  }

  double? get _departLat => (_demande?['depart_lat'] as num?)?.toDouble();
  double? get _departLng => (_demande?['depart_lng'] as num?)?.toDouble();

  Future<void> _calculerPositionEtEta() async {
    if (_departLat == null || _departLng == null) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (!mounted) return;
      final distanceKm = _haversineKm(
        position.latitude, position.longitude, _departLat!, _departLng!,
      );
      setState(() {
        _positionActuelle = LatLng(position.latitude, position.longitude);
        _etaMinutes = math.max(1, (distanceKm / _vitesseApprocheKmh * 60).round());
      });
    } catch (e) {
      debugPrint('[DemandeEntrante] Erreur position/ETA : $e');
    }
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }

  double _rad(double deg) => deg * math.pi / 180;

  /// Timer UX arrivé à 0 : ferme l'écran et tente un refus en best-effort.
  /// Ne s'exécute que si l'app est au premier plan (ce timer ne tourne que
  /// tant que ce widget est monté) — pas de garantie hors premier plan, le
  /// timeout autoritatif est côté serveur (Lot 3).
  Future<void> _expirer() async {
    if (_enTraitement || !mounted) return;
    setState(() => _enTraitement = true);
    try {
      await ApiService.refuserDemande(widget.demandeId);
    } catch (e) {
      debugPrint('[DemandeEntrante] Erreur refus après expiration : $e');
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _accepter() async {
    if (_enTraitement) return;
    setState(() => _enTraitement = true);
    _timerCompteARebours?.cancel();

    try {
      // La réponse contient la demande à jour (statut 'en_route') : le
      // backend ne renvoie client_telephone qu'à partir de ce statut, jamais
      // avant — ma copie locale _demande (récupérée avant l'acceptation) l'a
      // forcément à null, donc je ne dois pas m'y fier ici.
      final demandeAcceptee = await ApiService.accepterDemande(widget.demandeId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EcranNavigation(
            demandeId: widget.demandeId,
            destination: demandeAcceptee['destination']?.toString() ?? '',
            positionClient: (_departLat != null && _departLng != null)
                ? LatLng(_departLat!, _departLng!)
                : null,
            telephoneClient: demandeAcceptee['client_telephone']?.toString(),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demande déjà prise.')),
        );
        Navigator.of(context).maybePop();
      } else if (e.statusCode == 404) {
        Navigator.of(context).maybePop();
      } else {
        setState(() => _enTraitement = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _enTraitement = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _ignorer() async {
    if (_enTraitement) return;
    setState(() => _enTraitement = true);
    _timerCompteARebours?.cancel();

    try {
      await ApiService.refuserDemande(widget.demandeId);
    } catch (e) {
      // 404 = déjà résolue/expirée entre-temps : on ferme quand même, il n'y
      // a plus rien à refuser.
      debugPrint('[DemandeEntrante] Erreur refus : $e');
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Pas de retour arrière accidentel pendant le traitement d'un tap.
      canPop: !_enTraitement,
      child: Scaffold(
        backgroundColor: CouleursTaama.indigo,
        body: SafeArea(
          child: _chargement
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _demandeIntrouvable
                  ? _buildDemandeIntrouvable()
                  : _buildContenu(),
        ),
      ),
    );
  }

  Widget _buildDemandeIntrouvable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Cette demande n\'est plus disponible.',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Retour', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenu() {
    final demande = _demande!;
    final destination = demande['destination']?.toString() ?? '';
    final typeTransport = demande['type_transport']?.toString() ?? '';
    final prixEstime = demande['prix_estime'];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildCompteARebours(),
          const SizedBox(height: 20),
          if (_departLat != null && _departLng != null) ...[
            _buildMiniCarteDepart(),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flag, color: CouleursTaama.terreCuite),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            destination,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      typeTransport,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    if (_etaMinutes != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text(
                            '~$_etaMinutes min pour rejoindre le client',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      '$prixEstime FCFA',
                      style: const TextStyle(
                        color: CouleursTaama.terreCuite,
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildBoutons(),
        ],
      ),
    );
  }

  Widget _buildCompteARebours() {
    final proportion = _secondesRestantes / _dureeCompteARebours;
    return Column(
      children: [
        const Text(
          'Nouvelle demande',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: proportion,
                strokeWidth: 4,
                backgroundColor: Colors.white24,
                color: Colors.white,
              ),
              Text(
                '$_secondesRestantes',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniCarteDepart() {
    final depart = LatLng(_departLat!, _departLng!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 140,
        child: FlutterMap(
          options: MapOptions(initialCenter: depart, initialZoom: 14.5),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.taama.conducteur',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: depart,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.location_on, color: CouleursTaama.terreCuite, size: 36),
                ),
                if (_positionActuelle != null)
                  Marker(
                    point: _positionActuelle!,
                    width: 32,
                    height: 32,
                    child: const Icon(Icons.directions_car, color: CouleursTaama.indigo, size: 28),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoutons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _enTraitement ? null : _ignorer,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Ignorer', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _enTraitement ? null : _accepter,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _enTraitement
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Accepter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
