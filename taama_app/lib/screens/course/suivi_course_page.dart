// lib/screens/course/suivi_course_page.dart
//
// Pont entre les vraies données (polling REST + WebSocket de localisation
// LocationConsumer, via LocationService — voir services/location_service.dart)
// et SuiviCourseScreen, widget purement présentationnel (voir
// suivi_course_screen.dart). Remplace EcranSuiviDemande dans la navigation ;
// l'ancien écran reste disponible sous suivi_demande_screen_legacy.dart
// (non supprimé).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../services/routing_service.dart';
import '../../utils/format.dart';
import '../../widgets/widget_sos.dart';
import '../chat_screen.dart';
import 'suivi_course_screen.dart';

class SuiviCoursePage extends StatefulWidget {
  const SuiviCoursePage({
    super.key,
    required this.demandeId,
    required this.destination,
    required this.typeTransport,
  });

  final int demandeId;
  final String destination;
  final String typeTransport;

  @override
  State<SuiviCoursePage> createState() => _SuiviCoursePageState();
}

class _SuiviCoursePageState extends State<SuiviCoursePage> {
  static const Duration _intervallePolling = Duration(seconds: 3);

  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();
  Timer? _timerPolling;

  String _statutBrut = 'en_recherche';
  Map<String, dynamic>? _chauffeurBrut;
  int? _prixEstime;
  int _soldeFcfa = 0;

  // Fin de course : reflètent toujours la dernière réponse serveur, jamais
  // un état optimiste local — pour rester correctes même si l'app est
  // fermée puis rouverte entre-temps (voir brief).
  bool _paye = false;
  bool _dejaNote = false;
  bool _paiementEnCours = false;
  bool _noteEnCours = false;

  LatLng? _positionDepart;
  LatLng? _positionDestination;
  LatLng? _positionChauffeur;
  List<LatLng> _itineraire = [];
  int? _minutesAvantArrivee;
  double? _distanceKm;

  bool _suiviPositionDemarre = false;

  /// Dernier statut pour lequel l'itinéraire OSRM a été (re)chargé — permet
  /// de ne recharger qu'à un CHANGEMENT de statut, jamais à chaque position
  /// GPS reçue (l'itinéraire lui-même ne bouge pas entre deux points d'un
  /// même trajet, seul le marqueur du chauffeur bouge).
  String? _statutItineraireCharge;

  @override
  void initState() {
    super.initState();
    _chargerSolde();
    _rafraichir();
    _timerPolling =
        Timer.periodic(_intervallePolling, (_) => _rafraichir());
  }

  @override
  void dispose() {
    _timerPolling?.cancel();
    _locationService.arreter();
    super.dispose();
  }

  // ─── Chargement des données ───────────────────────────────────────────

  Future<void> _chargerSolde() async {
    try {
      final solde = await ApiService.monSolde();
      if (!mounted) return;
      setState(() => _soldeFcfa = solde);
    } catch (e) {
      debugPrint('[SuiviCoursePage] Erreur chargement solde : $e');
    }
  }

  Future<void> _rafraichir() async {
    try {
      final demande = await ApiService.detailDemande(widget.demandeId);
      if (!mounted) return;

      final nouveauStatut = demande['statut']?.toString() ?? _statutBrut;
      final prixRaw = demande['prix_estime'];

      var depart = _positionDepart;
      final departLat = demande['depart_lat'];
      final departLng = demande['depart_lng'];
      if (departLat != null && departLng != null) {
        depart = LatLng(
          (departLat as num).toDouble(),
          (departLng as num).toDouble(),
        );
      }

      var destination = _positionDestination;
      final destLat = demande['destination_lat'];
      final destLng = demande['destination_lng'];
      if (destLat != null && destLng != null) {
        destination = LatLng(
          (destLat as num).toDouble(),
          (destLng as num).toDouble(),
        );
      }

      setState(() {
        _statutBrut = nouveauStatut;
        _chauffeurBrut = demande['chauffeur'] as Map<String, dynamic>?;
        _prixEstime =
            prixRaw is int ? prixRaw : int.tryParse(prixRaw?.toString() ?? '');
        _positionDepart = depart;
        _positionDestination = destination;
        _paye = demande['paye'] as bool? ?? false;
        _dejaNote = demande['deja_note'] as bool? ?? false;
      });

      // La course a été annulée (par le chauffeur, un opérateur, ou par
      // l'utilisateur lui-même ailleurs) : SuiviCourseScreen ne modélise
      // aucun état "annulée" (voir rapport), donc on quitte l'écran plutôt
      // que d'afficher un état trompeur.
      if (nouveauStatut == 'annule') {
        _timerPolling?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cette course a été annulée.')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        });
        return;
      }

      // Le conducteur a signalé l'arrivée (terminer_course, indépendant du
      // paiement — voir trajets/views.py) : on arrête le polling, le reste
      // (paiement, notation) est piloté par action utilisateur.
      if (nouveauStatut == 'termine') {
        _timerPolling?.cancel();
      }

      // client_a_bord : le suivi GPS continue, c'est la 2e jambe du trajet.
      if (nouveauStatut == 'en_route' || nouveauStatut == 'client_a_bord') {
        _demarrerSuiviPosition();
      } else if (_suiviPositionDemarre) {
        _locationService.arreter();
        _suiviPositionDemarre = false;
        if (mounted) setState(() => _positionChauffeur = null);
      }

      if (_statutItineraireCharge != nouveauStatut) {
        _statutItineraireCharge = nouveauStatut;
        unawaited(_rechargerItineraire());
      }
    } catch (e) {
      debugPrint('[SuiviCoursePage] Erreur rafraîchissement demande : $e');
    }
  }

  /// Connecte le WebSocket de localisation (LocationConsumer côté backend)
  /// dès que le conducteur est en route, pour faire bouger le marqueur en
  /// temps réel sur la carte.
  void _demarrerSuiviPosition() {
    if (_suiviPositionDemarre) return;
    _suiviPositionDemarre = true;

    _locationService.ecouterPosition('${widget.demandeId}', (lat, lng) {
      if (!mounted) return;
      setState(() => _positionChauffeur = LatLng(lat, lng));
    });
  }

  LatLng? get _pointCible =>
      _statutBrut == 'client_a_bord' ? _positionDestination : _positionDepart;

  Future<void> _rechargerItineraire() async {
    final origine = _positionChauffeur ?? _positionDepart;
    final cible = _pointCible;
    if (origine == null || cible == null) return;

    final trace = await RoutingService.recupererItineraire(
      depart: origine,
      arrivee: cible,
    );
    final duree = await RoutingService.dureeMinutesVers(
      depart: origine,
      arrivee: cible,
    );
    if (!mounted) return;

    setState(() {
      _itineraire = trace ?? const [];
      _minutesAvantArrivee = duree;
      _distanceKm =
          (trace == null || trace.length < 2) ? null : _longueurKm(trace);
    });
  }

  double _longueurKm(List<LatLng> points) {
    const calculDistance = Distance();
    var metres = 0.0;
    for (var i = 0; i < points.length - 1; i++) {
      metres += calculDistance(points[i], points[i + 1]);
    }
    return metres / 1000;
  }

  // ─── Mapping vers le widget présentationnel ────────────────────────────

  StatutCourse get _statut => switch (_statutBrut) {
        'en_recherche' => StatutCourse.recherche,
        'chauffeur_trouve' => StatutCourse.acceptee,
        'en_route' => StatutCourse.enRoute,
        'client_a_bord' => StatutCourse.aBord,
        'termine' => StatutCourse.terminee,
        _ => StatutCourse.recherche,
      };

  ChauffeurCourse? get _chauffeur {
    final c = _chauffeurBrut;
    if (c == null) return null;

    final marque = c['marque']?.toString() ?? '';
    final modele = c['modele']?.toString() ?? '';
    final vehicule = '$marque $modele'.trim();
    final noteRaw = c['note'];
    final nombreCoursesRaw = c['nombre_courses'];

    return ChauffeurCourse(
      nomCourt: c['nom']?.toString() ?? 'Conducteur',
      plaque: c['plaque']?.toString() ?? '',
      urlPhoto: c['photo_profil']?.toString(),
      note: noteRaw == null ? null : double.tryParse(noteRaw.toString()),
      nombreCourses: nombreCoursesRaw is int
          ? nombreCoursesRaw
          : int.tryParse(nombreCoursesRaw?.toString() ?? ''),
      vehicule: vehicule.isEmpty ? null : vehicule,
      couleurVehicule: couleurVehicule(c['couleur'] as String?),
    );
  }

  // ─── Actions ────────────────────────────────────────────────────────────

  Future<void> _annuler() async {
    try {
      final reponse = await ApiService.annulerDemande(widget.demandeId);
      _timerPolling?.cancel();
      if (!mounted) return;
      final penalite = reponse['penalite'] as int? ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            penalite > 0
                ? 'Course annulée. Pénalité : $penalite FCFA'
                : 'Course annulée.',
          ),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _payer(MoyenPaiement moyen) async {
    if (moyen == MoyenPaiement.especes) {
      // Aucun endpoint de paiement en espèces côté backend — payer_demande
      // débite uniquement le portefeuille Taama (voir trajets/views.py).
      // Marquer `paye` ici serait un faux succès : le montant ne serait
      // jamais réellement encaissé côté serveur.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le paiement en espèces n\'est pas encore pris en charge par l\'application.',
          ),
        ),
      );
      return;
    }

    setState(() => _paiementEnCours = true);
    try {
      await ApiService.payerDemande(widget.demandeId);
      if (!mounted) return;
      setState(() => _paiementEnCours = false);
      // Resynchronise dejaPayee/soldeFcfa depuis le serveur plutôt que de
      // les déduire localement (voir brief).
      await Future.wait([_rafraichir(), _chargerSolde()]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _paiementEnCours = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors du paiement')),
      );
    }
  }

  Future<void> _noter(int etoiles, String? commentaire) async {
    setState(() => _noteEnCours = true);
    try {
      await ApiService.noterChauffeurDemande(
        widget.demandeId,
        etoiles,
        commentaire ?? '',
      );
      if (!mounted) return;
      setState(() => _noteEnCours = false);
      await _rafraichir();
    } catch (e) {
      if (!mounted) return;
      setState(() => _noteEnCours = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de l\'envoi de la note')),
      );
    }
  }

  void _ouvrirChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EcranChat(
          roomName: 'demande_${widget.demandeId}',
          titreConversation: _chauffeurBrut?['nom']?.toString() ?? 'Conducteur',
        ),
      ),
    );
  }

  /// URL de suivi public à partager. Toujours `null` pour l'instant : aucun
  /// endpoint de suivi public n'existe côté backend (vérifié dans
  /// trajets/urls.py) — je ne fabrique donc jamais de lien factice.
  String? _lienSuiviPublic() => null;

  Future<void> _partager() async {
    final lien = _lienSuiviPublic();
    if (lien == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le partage du suivi n\'est pas encore disponible.'),
        ),
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(text: lien, subject: 'Suivi de ma course Taama'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SuiviCourseScreen(
      statut: _statut,
      chauffeur: _chauffeur,
      mapController: _mapController,
      // ⚠️ L'API ne renvoie aucune adresse textuelle de départ (seulement
      // depart_lat/depart_lng) — voir DemandeInstantaneeSerializer. Libellé
      // générique plutôt qu'une adresse inventée (voir rapport).
      depart: 'Point de départ',
      arrivee: widget.destination,
      prixFcfa: _prixEstime ?? 0,
      soldeFcfa: _soldeFcfa,
      positionClient: _positionDepart,
      positionDestination: _positionDestination,
      positionChauffeur: _positionChauffeur,
      itineraire: _itineraire,
      minutesAvantArrivee: _minutesAvantArrivee,
      distanceKm: _distanceKm,
      // Aucune phrase de situation calculée côté serveur pour l'instant —
      // jamais de texte inventé côté app.
      phraseSituation: null,
      onRetour: () => Navigator.of(context).maybePop(),
      onSos: () => afficherDialogueSOS(context, demandeId: widget.demandeId),
      onPartager: _partager,
      onRecentrer: _positionDepart == null
          ? null
          : () => _mapController.move(_positionDepart!, 15.5),
      onAnnuler: _annuler,
      onAppeler: null, // ChauffeurSerializer n'expose aucun téléphone (voir rapport)
      onMessage: _chauffeurBrut == null ? null : _ouvrirChat,
      paiementEnCours: _paiementEnCours,
      dejaPayee: _paye,
      onPayer: _payer,
      noteEnCours: _noteEnCours,
      dejaNotee: _dejaNote,
      onNoter: _noter,
      onTerminer: () => Navigator.of(context).popUntil((route) => route.isFirst),
    );
  }
}
