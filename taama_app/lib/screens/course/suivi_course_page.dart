// lib/screens/course/suivi_course_page.dart
//
// Pont entre les vraies données (polling REST + WebSocket de localisation
// LocationConsumer, via LocationService — voir services/location_service.dart)
// et SuiviCourseScreen, widget purement présentationnel (voir
// suivi_course_screen.dart). Remplace l'ancien EcranSuiviDemande dans la
// navigation (supprimé, voir l'historique git).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_service.dart';
import '../../services/config_app.dart';
import '../../services/location_service.dart';
import '../../services/routing_service.dart';
import '../../utils/format.dart';
import '../../widgets/widget_sos.dart';
import '../chat_screen.dart';
import '../resultats_recherche_screen.dart';
import 'suivi_course_screen.dart';

/// Texte du bandeau d'état du suivi, ou null si tout va bien. Séparé de
/// l'écran pour être testé sans WebSocket.
@visibleForTesting
String? etatSuiviChauffeur({
  required bool suiviDemarre,
  required bool? connecte,
  required DateTime? dernierePositionLe,
  required bool positionConnue,
  required DateTime maintenant,
  required Duration ageMax,
}) {
  if (!suiviDemarre) return null;
  if (connecte == false) return 'Reconnexion au suivi…';
  if (!positionConnue || dernierePositionLe == null) return 'Localisation du chauffeur…';
  if (maintenant.difference(dernierePositionLe) > ageMax) {
    return 'Position en cours de mise à jour…';
  }
  return null;
}

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

class _SuiviCoursePageState extends State<SuiviCoursePage> with WidgetsBindingObserver {
  static const Duration _intervallePolling = Duration(seconds: 3);

  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();
  Timer? _timerPolling;

  String _statutBrut = 'en_recherche';
  bool _aucunChauffeurAffiche = false;
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

  /// Faux en arrière-plan : une réponse de _rafraichir arrivée après la
  /// suspension ne doit pas rouvrir le WebSocket de position.
  bool _enPremierPlan = true;

  /// Dernier statut traité : à chaque nouvelle étape (vers le client, puis
  /// vers la destination), l'ancien temps d'arrivée est effacé.
  String? _statutItineraireCharge;

  /// Dernier calcul OSRM : refait quand le chauffeur a bougé d'au moins
  /// [_deplacementRecalcul] ou après [_ageMaxItineraire], jamais plus d'un
  /// calcul à la fois (data mobile).
  static const double _deplacementRecalcul = 150; // mètres
  static const Duration _ageMaxItineraire = Duration(seconds: 30);
  LatLng? _positionItineraire;
  DateTime? _itineraireCalculeLe;
  bool _calculItineraireEnCours = false;

  /// État du suivi temps réel, pour ne jamais figer le marqueur en silence.
  static const Duration _ageMaxPosition = Duration(seconds: 30);
  bool? _suiviConnecte;
  DateTime? _dernierePositionLe;
  Timer? _timerFraicheur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chargerSolde();
    _rafraichir();
    _timerPolling =
        Timer.periodic(_intervallePolling, (_) => _rafraichir());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerPolling?.cancel();
    _arreterSuiviPosition();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    switch (etat) {
      case AppLifecycleState.resumed:
        _reprendreSuivi();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _suspendreSuivi();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// En arrière-plan : on coupe le polling 3 s et le WebSocket de position
  /// (data/batterie ; le WebSocket serait de toute façon coupé par l'OS).
  void _suspendreSuivi() {
    _enPremierPlan = false;
    _timerPolling?.cancel();
    _timerPolling = null;
    if (_suiviPositionDemarre) _arreterSuiviPosition();
  }

  /// Au retour au premier plan : on recharge l'état tout de suite et on
  /// relance polling + WebSocket (via _rafraichir), sauf course déjà finie.
  void _reprendreSuivi() {
    _enPremierPlan = true;
    if (_statutBrut == 'termine' || _statutBrut == 'annule') return;
    _rafraichir();
    _timerPolling?.cancel();
    _timerPolling = Timer.periodic(_intervallePolling, (_) => _rafraichir());
  }

  // ─── Chargement des données ───────────────────────────────────────────

  Future<void> _chargerSolde() async {
    // Mode gratuit : aucun solde affiché, donc aucune requête.
    if (!ConfigApp.paiementActif.value) return;
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
        if (demande['aucun_chauffeur_trouve'] == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _afficherAucunChauffeurTrouve();
          });
          return;
        }
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
        _arreterSuiviPosition();
        if (mounted) setState(() => _positionChauffeur = null);
      }

      if (_statutItineraireCharge != nouveauStatut) {
        _statutItineraireCharge = nouveauStatut;
        // Nouvelle étape : l'ancien temps ne vaut plus rien. Il est
        // recalculé dès qu'on connaît la vraie position du chauffeur.
        setState(() {
          _minutesAvantArrivee = null;
          _distanceKm = null;
          _itineraire = const [];
          _positionItineraire = null;
        });
        unawaited(_mettreAJourItineraire(force: true));
      }
    } catch (e) {
      debugPrint('[SuiviCoursePage] Erreur rafraîchissement demande : $e');
    }
  }

  /// Connecte le WebSocket de localisation (LocationConsumer côté backend)
  /// dès que le conducteur est en route, pour faire bouger le marqueur en
  /// temps réel sur la carte.
  void _demarrerSuiviPosition() {
    if (_suiviPositionDemarre || !_enPremierPlan) return;
    _suiviPositionDemarre = true;
    _suiviConnecte = null; // connexion en cours

    _locationService.ecouterPosition(
      '${widget.demandeId}',
      (lat, lng) {
        if (!mounted) return;
        setState(() {
          _positionChauffeur = LatLng(lat, lng);
          _dernierePositionLe = DateTime.now();
        });
        unawaited(_mettreAJourItineraire());
      },
      onConnexion: (connecte) {
        if (mounted) setState(() => _suiviConnecte = connecte);
      },
    );
    // Réévalue « position périmée » même quand plus rien n'arrive.
    _timerFraicheur ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  void _arreterSuiviPosition() {
    _locationService.arreter();
    _suiviPositionDemarre = false;
    _suiviConnecte = null;
    _timerFraicheur?.cancel();
    _timerFraicheur = null;
  }

  LatLng? get _pointCible =>
      _statutBrut == 'client_a_bord' ? _positionDestination : _positionDepart;

  /// Temps et distance depuis la VRAIE position du chauffeur, jamais depuis
  /// le point de prise en charge : sans position, aucun temps affiché
  /// (l'ancien calcul partait du départ vers lui-même → « 0 min · 0 m »).
  Future<void> _mettreAJourItineraire({bool force = false}) async {
    final origine = _positionChauffeur;
    final cible = _pointCible;
    if (origine == null || cible == null || _calculItineraireEnCours) return;
    if (!force && _positionItineraire != null && _itineraireCalculeLe != null) {
      final bouge = const Distance().as(LengthUnit.Meter, _positionItineraire!, origine);
      final age = DateTime.now().difference(_itineraireCalculeLe!);
      if (bouge < _deplacementRecalcul && age < _ageMaxItineraire) return;
    }
    _calculItineraireEnCours = true;
    _positionItineraire = origine;
    _itineraireCalculeLe = DateTime.now();
    try {
      final r = await RoutingService.calculerItineraire(depart: origine, arrivee: cible);
      // OSRM indisponible : on garde la dernière valeur connue (ou rien).
      if (!mounted || r == null) return;
      setState(() {
        _itineraire = r.trace;
        _minutesAvantArrivee = r.minutes;
        _distanceKm = r.km;
      });
    } finally {
      _calculItineraireEnCours = false;
    }
  }

  /// Bandeau sur la carte : jamais un marqueur figé sans explication.
  String? get _etatSuivi => etatSuiviChauffeur(
        suiviDemarre: _suiviPositionDemarre,
        connecte: _suiviConnecte,
        dernierePositionLe: _dernierePositionLe,
        positionConnue: _positionChauffeur != null,
        maintenant: DateTime.now(),
        ageMax: _ageMaxPosition,
      );

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

    // Libellé dédupliqué du serveur (Chauffeur.vehicule_libelle) ; repli
    // sur la même règle côté app si un serveur plus ancien ne l'envoie pas.
    final vehiculeServeur = c['vehicule']?.toString().trim() ?? '';
    final vehicule = vehiculeServeur.isNotEmpty
        ? vehiculeServeur
        : libelleVehicule(c['marque']?.toString(), c['modele']?.toString());
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
      vehicule: vehicule,
      couleurVehicule: couleurVehicule(c['couleur'] as String?),
      couleurLibelle: couleurVehiculeFeminin(c['couleur'] as String?),
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

  /// La recherche a dépassé son délai côté serveur. Réessayer repart d'une
  /// nouvelle estimation : un nouveau prix, jamais l'ancien devis.
  Future<void> _afficherAucunChauffeurTrouve() async {
    if (_aucunChauffeurAffiche) return;
    _aucunChauffeurAffiche = true;
    final reessayer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogue) => AlertDialog(
        title: const Text('Aucun chauffeur trouvé'),
        content: const Text('Aucun chauffeur n’est disponible près de vous pour le moment. Rien ne vous a été facturé.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogue, false),
            child: const Text('Fermer'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogue, true),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (reessayer == true) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EcranDemandeInstantanee(
            destination: widget.destination,
            destinationLat: _positionDestination?.latitude,
            destinationLng: _positionDestination?.longitude,
          ),
        ),
      );
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConfigApp.paiementActif,
      builder: (context, paiementActif, _) => _ecran(context, paiementActif),
    );
  }

  Widget _ecran(BuildContext context, bool paiementActif) {
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
      paiementActif: paiementActif,
      positionClient: _positionDepart,
      positionDestination: _positionDestination,
      positionChauffeur: _positionChauffeur,
      itineraire: _itineraire,
      minutesAvantArrivee: _minutesAvantArrivee,
      distanceKm: _distanceKm,
      // Aucune phrase de situation calculée côté serveur pour l'instant —
      // jamais de texte inventé côté app.
      phraseSituation: null,
      etatSuivi: _etatSuivi,
      onRetour: () => Navigator.of(context).maybePop(),
      onSos: () => afficherDialogueSOS(context, demandeId: widget.demandeId),
      // Partage masqué : aucun suivi public côté serveur (pas de bouton inerte).
      onPartager: null,
      onRecentrer: _positionDepart == null
          ? null
          : () => _mapController.move(_positionDepart!, 15.5),
      onAnnuler: _annuler,
      onAppeler: null, // ChauffeurSerializer n'expose aucun téléphone (voir rapport)
      onMessage: _chauffeurBrut == null ? null : _ouvrirChat,
      paiementEnCours: _paiementEnCours,
      dejaPayee: _paye,
      onPayer: paiementActif ? _payer : null,
      noteEnCours: _noteEnCours,
      dejaNotee: _dejaNote,
      onNoter: _noter,
      onTerminer: () => Navigator.of(context).popUntil((route) => route.isFirst),
    );
  }
}
