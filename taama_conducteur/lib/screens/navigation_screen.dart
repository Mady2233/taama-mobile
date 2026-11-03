// DESIGN_V4
//
// Navigation du conducteur.
//
// Inchangé : calcul OSRM, voix (TTS), flux GPS en service de premier plan,
// envoi de la position au client (LocationService), passage « client à
// bord » (marquerClientABord), fin de course (terminerCourse).
//
// Nouveau :
// - carte fixée plein nord (plus de texte à l'envers), flèche du chauffeur
//   qui tourne selon son cap ;
// - bandeau de la prochaine manœuvre à l'écran (icône + distance), en plus
//   de la voix ;
// - suivi automatique de la carte, suspendu quand le chauffeur la déplace,
//   avec bouton « Recentrer » ;
// - boutons explicites « Client à bord » et « Terminer la course » (avec
//   confirmation), en plus de la détection automatique à 100 m ;
// - « Quitter » ne prétend plus terminer la course ;
// - « Ouvrir dans Google Maps » ;
// - si la position du client est introuvable : message clair, jamais de
//   repli sur le centre de Bamako (qui guidait au mauvais endroit) ;
// - si OSRM ne répond pas : message + Google Maps, au lieu d'une carte vide.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../theme/couleurs_taama.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';
import '../widgets/couche_carte_taama.dart';
import '../carte/fond_carte.dart';

/// Convertit le champ JSON brut `arrets` d'une demande (venant de l'API,
/// voir ArretDemandeSerializer côté backend) en liste triée par ordre, prête
/// pour [EcranNavigation.arrets]. Défensif : l'API renvoie déjà les arrêts
/// triés (Meta.ordering du modèle), mais un tri explicite ici ne coûte rien
/// et protège contre un futur changement de comportement du backend.
List<Map<String, dynamic>> extraireArrets(dynamic arretsJson) {
  if (arretsJson is! List) return const [];
  final arrets = arretsJson.cast<Map<String, dynamic>>().toList()
    ..sort((a, b) => (a['ordre'] as num).compareTo(b['ordre'] as num));
  return arrets;
}

/// Une instruction de navigation ("tournez à droite", ...) associée au point
/// GPS où elle doit être annoncée, extraite des "steps" retournés par OSRM.
class _EtapeNavigation {
  final LatLng position;
  final String instruction;
  final IconData icone;

  const _EtapeNavigation({
    required this.position,
    required this.instruction,
    required this.icone,
  });
}

/// Hauteur réservée en bas pour le panneau d'actions (attribution et badges
/// se placent au-dessus).
const double _hauteurPanneau = 186;

/// Écran de navigation GPS pour le conducteur.
/// Affiche l'itinéraire entre sa position actuelle et le client,
/// calculé via l'API OSRM (Open Source Routing Machine - gratuit).
class EcranNavigation extends StatefulWidget {
  final int demandeId;
  final String destination;
  final LatLng? positionClient; // Si connue, sinon on utilise le géocodage
  final String? telephoneClient;
  // Position réelle de la destination du client (géocodée à la création de
  // la demande) — permet une 2e jambe de navigation une fois le client
  // récupéré. Absente sur une demande créée avant ce champ, ou si le
  // géocodage avait échoué côté app cliente : dans ce cas, comportement
  // historique inchangé (une seule jambe, jusqu'au point de départ).
  final double? destinationLat;
  final double? destinationLng;
  // Arrêts intermédiaires du passager, DANS L'ORDRE, entre son point de
  // départ et sa destination finale (voir extraireArrets ci-dessus pour les
  // obtenir depuis la réponse API brute) — pris en compte uniquement sur la
  // 2e jambe (client à bord), jamais sur la 1re (aller chercher le client,
  // qui n'a rien à voir avec ses arrêts).
  final List<Map<String, dynamic>> arrets;

  /// Navigation rouverte alors que le client est déjà à bord (statut
  /// 'client_a_bord') : [positionClient] est alors SA DESTINATION, et l'écran
  /// démarre directement en 2e jambe (libellés « Course », drapeau,
  /// « Terminer la course »). Les arrêts ne sont pas repris dans le calcul
  /// d'itinéraire : on ne sait pas lesquels sont déjà passés.
  final bool clientDejaABord;

  const EcranNavigation({
    super.key,
    required this.demandeId,
    required this.destination,
    this.positionClient,
    this.telephoneClient,
    this.destinationLat,
    this.destinationLng,
    this.arrets = const [],
    this.clientDejaABord = false,
  });

  @override
  State<EcranNavigation> createState() => _EcranNavigationState();
}

class _EcranNavigationState extends State<EcranNavigation> {
  final MapController _mapController = MapController();
  final LocationService _locationService = LocationService();
  final FlutterTts _tts = FlutterTts();

  LatLng? _positionConducteur;
  LatLng? _positionClient;
  List<LatLng> _itineraire = [];

  // Instructions de navigation extraites des "steps" OSRM
  List<_EtapeNavigation> _etapes = [];
  int _etapeIndex = 0;
  bool _etapeAnnoncee = false;

  double? _distanceKm;
  int? _dureeMinutes;
  double _vitesseKmh = 0;

  bool _chargement = true;
  bool _navigationDemarree = false;
  bool _arriveeDetectee = false;
  // false = 1re jambe (vers le point de départ du client) ; true = 2e jambe
  // (client à bord, vers sa destination).
  bool _jambeVersDestination = false;
  StreamSubscription<Position>? _positionStream;

  // ─── Affichage (nouveau) ───
  bool _cartePrete = false;
  bool _suivre = true; // la carte suit le chauffeur tant qu'il ne la déplace pas
  bool _erreurItineraire = false;
  bool _positionClientIntrouvable = false;
  // Sans position du chauffeur, aucun itinéraire : jamais une carte vide
  // sans explication (voir _bandeauProbleme).
  LocationPermission? _permissionRefusee; // denied ou deniedForever
  bool _gpsIndisponible = false;
  double _capAffiche = 0; // degrés, cumulés (rotation par le plus court chemin)
  bool _actionEnCours = false;

  LatLng? get _positionDestinationReelle {
    if (widget.destinationLat == null || widget.destinationLng == null) return null;
    return LatLng(widget.destinationLat!, widget.destinationLng!);
  }

  @override
  void initState() {
    super.initState();
    _jambeVersDestination = widget.clientDejaABord;
    _initialiserTts();
    _initialiser();
  }

  Future<void> _initialiserTts() async {
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _locationService.arreter();
    _tts.stop();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initialiser() async {
    // 1. Vérifie les permissions GPS
    final permission = await _verifierPermissions();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _permissionRefusee = permission;
          _chargement = false;
        });
      }
      return;
    }

    // 2. Récupère la position actuelle du conducteur
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _positionConducteur = LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('[Navigation] Erreur position conducteur : $e');
    }
    _gpsIndisponible = _positionConducteur == null;

    // 3. Utilise la position client fournie ou celle géocodée
    _positionClient = widget.positionClient ?? await _recupererPositionClient();
    _positionClientIntrouvable = _positionClient == null;

    // 4. Calcule l'itinéraire via OSRM
    if (_positionConducteur != null && _positionClient != null) {
      await _calculerItineraire();
    }

    if (!mounted) return;
    setState(() => _chargement = false);

    // 5. Centre la carte sur les deux points
    _centrerCarte();
  }

  Future<LocationPermission> _verifierPermissions() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  /// Bouton « Réessayer » des bandeaux GPS : relance toute l'initialisation.
  Future<void> _reessayerInitialisation() async {
    if (_chargement) return;
    setState(() {
      _chargement = true;
      _permissionRefusee = null;
      _gpsIndisponible = false;
      _positionClientIntrouvable = false;
      _erreurItineraire = false;
    });
    await _initialiser();
  }

  /// Bandeau du problème le plus bloquant, ou null s'il n'y en a pas.
  Widget? _bandeauProbleme() {
    if (_permissionRefusee == LocationPermission.deniedForever) {
      return _BandeauAlerte(
        texte: 'Localisation refusée. Autorise-la dans les réglages pour être guidé.',
        libelleAction: 'Réglages',
        onAction: () async {
          await Geolocator.openAppSettings();
          if (mounted) _reessayerInitialisation();
        },
      );
    }
    if (_permissionRefusee == LocationPermission.denied) {
      return _BandeauAlerte(
        texte: 'Autorise la localisation pour être guidé jusqu’au client.',
        libelleAction: 'Réessayer',
        onAction: _reessayerInitialisation,
      );
    }
    if (_gpsIndisponible) {
      return _BandeauAlerte(
        texte: 'Position GPS indisponible. Active la localisation et réessaie.',
        libelleAction: 'Réessayer',
        onAction: _reessayerInitialisation,
      );
    }
    if (_positionClientIntrouvable) {
      return const _BandeauAlerte(
        texte: 'Position du client introuvable. Appelle-le pour le localiser.',
      );
    }
    if (_erreurItineraire) {
      return const _BandeauAlerte(
        texte: "Itinéraire indisponible pour l'instant. Utilise Google Maps.",
      );
    }
    return null;
  }

  /// Géocode la destination via Nominatim. `null` si introuvable : on ne
  /// renvoie JAMAIS de position par défaut (l'ancien repli sur le centre de
  /// Bamako guidait le chauffeur au mauvais endroit).
  Future<LatLng?> _recupererPositionClient() async {
    try {
      final destination = Uri.encodeComponent(
        '${widget.destination}, Bamako, Mali'
      );
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=$destination&format=json&limit=1'
      );

      final reponse = await http.get(url, headers: {
        'User-Agent': AppConfig.userAgentHttp,
      }).timeout(const Duration(seconds: 10));

      if (reponse.statusCode == 200) {
        final resultats = jsonDecode(reponse.body) as List;
        if (resultats.isNotEmpty) {
          final lat = double.parse(resultats[0]['lat'].toString());
          final lon = double.parse(resultats[0]['lon'].toString());
          return LatLng(lat, lon);
        }
      }
    } catch (e) {
      debugPrint('[Navigation] Erreur géocodage : $e');
    }
    return null;
  }

  /// Ne recalcule l'itinéraire que si le conducteur s'est écarté de plus de
  /// 50m de la route tracée — évite de spammer OSRM à chaque tick de 3s.
  bool _estHorsItineraire() {
    if (_itineraire.isEmpty || _positionConducteur == null) return false;
    const Distance distance = Distance();
    double distanceMin = double.infinity;
    for (final point in _itineraire) {
      final d = distance(_positionConducteur!, point);
      if (d < distanceMin) distanceMin = d;
    }
    return distanceMin > 50;
  }

  String _texteInstruction(String type, String modifier) {
    if (type == 'roundabout' || type == 'rotary') {
      return 'prenez le rond-point';
    }
    switch (modifier) {
      case 'left':
        return 'tournez à gauche';
      case 'right':
        return 'tournez à droite';
      case 'slight left':
        return 'serrez légèrement à gauche';
      case 'slight right':
        return 'serrez légèrement à droite';
      case 'sharp left':
        return 'tournez fortement à gauche';
      case 'sharp right':
        return 'tournez fortement à droite';
      case 'uturn':
        return 'faites demi-tour';
      default:
        return 'continuez tout droit';
    }
  }

  IconData _iconeManoeuvre(String type, String modifier) {
    if (type == 'roundabout' || type == 'rotary') return Icons.roundabout_right_rounded;
    switch (modifier) {
      case 'left':
        return Icons.turn_left_rounded;
      case 'right':
        return Icons.turn_right_rounded;
      case 'slight left':
        return Icons.turn_slight_left_rounded;
      case 'slight right':
        return Icons.turn_slight_right_rounded;
      case 'sharp left':
        return Icons.turn_sharp_left_rounded;
      case 'sharp right':
        return Icons.turn_sharp_right_rounded;
      case 'uturn':
        return Icons.u_turn_left_rounded;
      default:
        return Icons.straight_rounded;
    }
  }

  Future<void> _calculerItineraire() async {
    if (_positionConducteur == null || _positionClient == null) return;

    try {
      // Arrêts intermédiaires uniquement sur la 2e jambe (client à bord), et
      // pas sur une navigation rouverte : certains sont peut-être déjà passés.
      final pointsVia = (_jambeVersDestination && !widget.clientDejaABord)
          ? widget.arrets
          : const [];

      final coords = [
        '${_positionConducteur!.longitude},${_positionConducteur!.latitude}',
        for (final a in pointsVia) '${a['longitude']},${a['latitude']}',
        '${_positionClient!.longitude},${_positionClient!.latitude}',
      ].join(';');
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$coords'
        '?overview=full&geometries=geojson&steps=true'
      );

      final reponse = await http.get(url).timeout(const Duration(seconds: 15));

      if (reponse.statusCode == 200) {
        final donnees = jsonDecode(reponse.body);

        if (donnees['code'] == 'Ok' && donnees['routes'].isNotEmpty) {
          final route = donnees['routes'][0];
          final geometry = route['geometry']['coordinates'] as List;

          // OSRM retourne [longitude, latitude] — on inverse pour LatLng
          final points = geometry.map((coord) {
            final c = coord as List;
            return LatLng(
              (c[1] as num).toDouble(),
              (c[0] as num).toDouble(),
            );
          }).toList();

          final distanceMetres = (route['distance'] as num).toDouble();
          final dureeSec = (route['duration'] as num).toDouble();

          final etapesBrutes = (route['legs'] as List)
              .expand((leg) => (leg['steps'] as List))
              .toList();
          final nouvellesEtapes = <_EtapeNavigation>[];
          for (final step in etapesBrutes) {
            final maneuver = step['maneuver'];
            final type = maneuver['type']?.toString() ?? '';
            if (type == 'depart' || type == 'arrive') continue;
            final modifier = maneuver['modifier']?.toString() ?? 'straight';
            final loc = maneuver['location'] as List;
            nouvellesEtapes.add(_EtapeNavigation(
              position: LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
              instruction: _texteInstruction(type, modifier),
              icone: _iconeManoeuvre(type, modifier),
            ));
          }

          if (!mounted) return;
          setState(() {
            _itineraire = points;
            _distanceKm = distanceMetres / 1000;
            _dureeMinutes = (dureeSec / 60).ceil();
            _etapes = nouvellesEtapes;
            _etapeIndex = 0;
            _etapeAnnoncee = false;
            _erreurItineraire = false;
          });
          return;
        }
      }
      if (mounted) setState(() => _erreurItineraire = true);
    } catch (e) {
      debugPrint('[Navigation] Erreur calcul itinéraire OSRM : $e');
      if (mounted) setState(() => _erreurItineraire = true);
    }
  }

  /// Annonce vocalement la prochaine instruction quand on s'en approche
  /// (~250m), puis passe à la suivante une fois le virage franchi.
  Future<void> _verifierInstructionVocale() async {
    if (_positionConducteur == null || _etapeIndex >= _etapes.length) return;

    const Distance distance = Distance();
    final etape = _etapes[_etapeIndex];
    final d = distance(_positionConducteur!, etape.position);

    if (!_etapeAnnoncee && d <= 250) {
      _etapeAnnoncee = true;
      final metres = ((d / 50).round() * 50).clamp(50, 250);
      await _tts.speak('Dans $metres mètres, ${etape.instruction}');
    } else if (d <= 25) {
      if (mounted) {
        setState(() {
          _etapeIndex++;
          _etapeAnnoncee = false;
        });
      }
    }
  }

  /// Détecte automatiquement l'arrivée au point suivi (< 100m). Sur la 1re
  /// jambe (vers le client), bascule vers la 2e jambe si une destination
  /// réelle est connue ; sinon (ou sur la 2e jambe), propose de terminer.
  Future<void> _verifierArrivee() async {
    if (_arriveeDetectee || _positionConducteur == null || _positionClient == null) return;

    const Distance distance = Distance();
    final d = distance(_positionConducteur!, _positionClient!);

    if (d <= 100) {
      _arriveeDetectee = true;

      if (!_jambeVersDestination && _positionDestinationReelle != null) {
        await _demarrerJambeVersDestination();
        return;
      }

      await _tts.speak('Vous êtes arrivé à destination');
      if (!mounted) return;
      _proposerFinDeCourse();
    }
  }

  /// Le conducteur vient d'atteindre le point de départ du client : signale
  /// "client à bord" au backend (best-effort, non bloquant — même en cas
  /// d'échec réseau, le guidage vers la destination continue, mieux vaut un
  /// statut pas à jour qu'un conducteur laissé sans itinéraire), puis
  /// bascule le point suivi vers la vraie destination et recalcule la route.
  Future<void> _demarrerJambeVersDestination() async {
    try {
      await ApiService.marquerClientABord(widget.demandeId);
    } catch (e) {
      debugPrint('[Navigation] Erreur marquer client à bord : $e');
    }

    final texteArrets = widget.arrets.isNotEmpty
        ? ' avec ${widget.arrets.length} arrêt${widget.arrets.length > 1 ? 's' : ''} en chemin'
        : '';
    await _tts.speak(
        'Client à bord. Direction : ${widget.destination}$texteArrets');
    if (!mounted) return;

    setState(() {
      _jambeVersDestination = true;
      _positionClient = _positionDestinationReelle;
      _arriveeDetectee = false;
      _etapes = [];
      _etapeIndex = 0;
      _etapeAnnoncee = false;
      _suivre = true;
    });

    await _calculerItineraire();
    _centrerCarte();
  }

  /// Bouton « Client à bord » : même effet que la détection à 100 m, pour
  /// quand le GPS dérive ou que le client attend un peu plus loin.
  Future<void> _clientABordManuel() async {
    if (_jambeVersDestination || _actionEnCours) return;
    final ok = await _confirmer(
      titre: 'Le client est à bord ?',
      texte: 'Le guidage passera vers sa destination : ${widget.destination}.',
      action: 'Oui, démarrer le trajet',
    );
    if (ok != true || !mounted) return;
    setState(() => _actionEnCours = true);
    _arriveeDetectee = true;
    try {
      await _demarrerJambeVersDestination();
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<bool?> _confirmer({
    required String titre,
    required String texte,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titre),
        content: Text(texte),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: CouleursTaama.terreCuite,
              foregroundColor: Colors.white,
            ),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  void _proposerFinDeCourse() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Terminer la course ?'),
        content: const Text('Le client est-il bien arrivé à destination ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Pas encore'),
          ),
          ElevatedButton(
            onPressed: () => _terminerCourse(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: CouleursTaama.terreCuite,
              foregroundColor: Colors.white,
            ),
            child: const Text('Terminer la course'),
          ),
        ],
      ),
    );
  }

  Future<void> _terminerCourse(BuildContext dialogContext) async {
    Navigator.pop(dialogContext);
    try {
      await ApiService.terminerCourse(widget.demandeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course terminée avec succès.')),
      );
      _locationService.arreter();
      _positionStream?.cancel();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString().replaceAll("Exception: ", "")}')),
      );
    }
  }

  /// Quitte l'écran SANS terminer la course (elle reste en cours ; on peut
  /// revenir via « Naviguer »).
  void _quitter() {
    _locationService.arreter();
    _positionStream?.cancel();
    Navigator.pop(context);
  }

  Future<void> _appelerClient() async {
    final numero = widget.telephoneClient;
    if (numero == null || numero.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: numero));
    } catch (e) {
      debugPrint('[Navigation] Erreur appel client : $e');
    }
  }

  /// Ouvre le point suivi dans Google Maps (ou l'app de cartes du téléphone).
  Future<void> _ouvrirGoogleMaps() async {
    final cible = _positionClient;
    if (cible == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${cible.latitude},${cible.longitude}'
      '&travelmode=driving',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Navigation] Erreur ouverture Google Maps : $e');
    }
  }

  void _centrerCarte() {
    if (_positionConducteur == null && _positionClient == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_cartePrete) return;

      if (_positionConducteur != null && _positionClient != null) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([_positionConducteur!, _positionClient!]),
            padding: EdgeInsets.fromLTRB(48, 200, 48, _hauteurPanneau + 40),
            maxZoom: 16,
          ),
        );
      } else {
        _mapController.move(_positionConducteur ?? _positionClient!, 14.0);
      }
    });
  }

  void _recentrer() {
    setState(() => _suivre = true);
    final p = _positionConducteur;
    if (p != null && _cartePrete) _mapController.move(p, 16.0);
  }

  /// Flux GPS continu (pas un Timer.periodic) protégé par un service en
  /// foreground (Android, notification persistante) / indicateur arrière-plan
  /// (iOS) — condition pour que la navigation continue de fonctionner écran
  /// verrouillé/app en arrière-plan pendant une course. Un Timer.periodic ne
  /// survivrait pas à la mise en arrière-plan de l'app.
  LocationSettings _parametresPositionNavigation() {
    const distanceFiltre = 10; // mètres
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFiltre,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Navigation en cours',
          notificationText: 'Ta position est partagée avec le client pendant la course.',
          enableWakeLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFiltre,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: distanceFiltre);
  }

  void _demarrerNavigation() {
    setState(() {
      _navigationDemarree = true;
      _suivre = true;
    });

    // Connexion WebSocket seule (pas de boucle GPS interne à LocationService)
    // : cet écran fournit sa propre position ci-dessous via envoyerPosition().
    _locationService.connecterPourEnvoi(widget.demandeId.toString());

    _positionStream = Geolocator.getPositionStream(
      locationSettings: _parametresPositionNavigation(),
    ).listen((position) async {
      if (!mounted) return;

      final nouvellePosition = LatLng(position.latitude, position.longitude);
      final vitesseKmh = (position.speed * 3.6).clamp(0, 300).toDouble();

      setState(() {
        _positionConducteur = nouvellePosition;
        _vitesseKmh = vitesseKmh;
        // Le cap n'a de sens qu'en mouvement (à l'arrêt, le GPS renvoie
        // souvent 0) : on garde la dernière direction connue.
        if (position.speed > 1.5 && position.heading >= 0) {
          final delta = ((position.heading - _capAffiche + 540) % 360) - 180;
          _capAffiche += delta;
        }
      });

      // Réutilise cette même position pour le client — pas de 2e requête
      // GPS séparée pour ça.
      _locationService.envoyerPosition(position.latitude, position.longitude);

      if (_estHorsItineraire()) {
        await _calculerItineraire();
      }

      await _verifierInstructionVocale();
      await _verifierArrivee();

      // Suit le chauffeur, sauf s'il a déplacé la carte à la main.
      if (_suivre && _cartePrete && mounted) {
        _mapController.move(nouvellePosition, 16.0);
      }
    }, onError: (e) {
      debugPrint('[Navigation] Erreur flux position : $e');
    });
  }

  // ─── Construction ───

  String get _heureArrivee {
    final duree = _dureeMinutes;
    if (duree == null) return '—';
    final h = DateTime.now().add(Duration(minutes: duree));
    return '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
  }

  /// Distance jusqu'à la prochaine manœuvre, arrondie pour l'affichage.
  String? get _distanceManoeuvre {
    if (_positionConducteur == null || _etapeIndex >= _etapes.length) return null;
    final d = const Distance()(_positionConducteur!, _etapes[_etapeIndex].position);
    if (d >= 1000) return '${(d / 1000).toStringAsFixed(1)} km';
    final arrondi = d < 100 ? (d / 10).round() * 10 : (d / 50).round() * 50;
    return '$arrondi m';
  }

  @override
  Widget build(BuildContext context) {
    final nuit = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final basSecurite = MediaQuery.paddingOf(context).bottom;
    final margeAttribution = EdgeInsets.only(
      right: 12,
      bottom: _hauteurPanneau + 8 + basSecurite,
    );
    final texte = nuit ? CouleursTaama.blanc : CouleursTaama.indigo;
    final panneau = nuit ? CouleursTaama.nuitPanneau : Colors.white;
    final reduit = MediaQuery.disableAnimationsOf(context);
    final duree = reduit ? Duration.zero : const Duration(milliseconds: 300);
    final etapeCourante =
        _etapeIndex < _etapes.length ? _etapes[_etapeIndex] : null;
    final probleme = _chargement ? null : _bandeauProbleme();

    return Scaffold(
      body: Stack(
        children: [
          // ─── Carte plein écran ───
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _positionConducteur ?? const LatLng(12.6392, -8.0029),
              initialZoom: 13.0,
              // Plein nord : la rotation retournait les noms de rue.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () {
                _cartePrete = true;
                _centrerCarte();
              },
              onPositionChanged: (camera, aGeste) {
                if (aGeste && _suivre && _navigationDemarree) {
                  setState(() => _suivre = false);
                }
              },
            ),
            children: [
              FondCarteTaama(nuit: nuit),
              CoucheCarteTaama(
                nuit: nuit,
                densite: DensiteEtiquettes.navigation,
                reserves: [
                  ZoneReservee.attribution(
                    alignement: Alignment.bottomRight,
                    marge: margeAttribution,
                  ),
                ],
              ),
              if (_itineraire.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    // Liseré sous le tracé : plus lisible sur le fond de carte.
                    Polyline(
                      points: _itineraire,
                      color: nuit ? Colors.black54 : Colors.white,
                      strokeWidth: 9.0,
                    ),
                    Polyline(
                      points: _itineraire,
                      color: nuit ? CouleursTaama.itineraireNuit : CouleursTaama.indigo,
                      strokeWidth: 5.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_positionClient != null)
                    Marker(
                      point: _positionClient!,
                      width: 70,
                      height: 70,
                      child: _MarqueurCible(
                        icone: _jambeVersDestination
                            ? Icons.flag_rounded
                            : Icons.person_pin_circle_rounded,
                      ),
                    ),
                  if (_jambeVersDestination)
                    for (var i = 0; i < widget.arrets.length; i++)
                      Marker(
                        point: LatLng(
                          (widget.arrets[i]['latitude'] as num).toDouble(),
                          (widget.arrets[i]['longitude'] as num).toDouble(),
                        ),
                        width: 32,
                        height: 32,
                        child: Container(
                          decoration: BoxDecoration(
                            color: CouleursTaama.or,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                  if (_positionConducteur != null)
                    Marker(
                      point: _positionConducteur!,
                      width: 56,
                      height: 56,
                      child: AnimatedRotation(
                        turns: _capAffiche / 360,
                        duration: reduit ? Duration.zero : const Duration(milliseconds: 400),
                        child: Container(
                          decoration: BoxDecoration(
                            color: nuit ? CouleursTaama.blanc : CouleursTaama.indigo,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: nuit ? CouleursTaama.indigo : Colors.white,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.navigation_rounded,
                            color: nuit ? CouleursTaama.indigo : Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              AttributionCarteTaama(
                nuit: nuit,
                alignement: Alignment.bottomRight,
                marge: margeAttribution,
              ),
            ],
          ),

          // ─── Haut : retour + manœuvre (ou titre) ───
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _BoutonRond(
                          icone: Icons.arrow_back_rounded,
                          info: 'Quitter la navigation',
                          onTap: _quitter,
                          nuit: nuit,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CartePhase(
                            versDestination: _jambeVersDestination,
                            destination: widget.destination,
                            nbArrets: widget.arrets.length,
                            nuit: nuit,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: duree,
                      transitionBuilder: (enfant, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, -0.3),
                            end: Offset.zero,
                          ).animate(animation),
                          child: enfant,
                        ),
                      ),
                      child: (_navigationDemarree && etapeCourante != null)
                          ? _BandeauManoeuvre(
                              key: ValueKey('etape_${_jambeVersDestination}_$_etapeIndex'),
                              icone: etapeCourante.icone,
                              instruction: etapeCourante.instruction,
                              distance: _distanceManoeuvre,
                            )
                          : const SizedBox.shrink(key: ValueKey('aucune_etape')),
                    ),
                    if (probleme != null) ...[
                      const SizedBox(height: 10),
                      probleme,
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ─── Boutons flottants à droite ───
          Positioned(
            right: 12,
            bottom: _hauteurPanneau + 40 + basSecurite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: _suivre ? 0 : 1,
                  duration: duree,
                  curve: Curves.easeOutBack,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _BoutonRond(
                      icone: Icons.my_location_rounded,
                      info: 'Recentrer',
                      onTap: _recentrer,
                      nuit: nuit,
                    ),
                  ),
                ),
                if (widget.telephoneClient != null && widget.telephoneClient!.isNotEmpty) ...[
                  _BoutonRond(
                    icone: Icons.phone_rounded,
                    info: 'Appeler le client',
                    onTap: _appelerClient,
                    nuit: nuit,
                    accent: true,
                  ),
                  const SizedBox(height: 10),
                ],
                if (_positionClient != null)
                  _BoutonRond(
                    icone: Icons.map_rounded,
                    info: 'Ouvrir dans Google Maps',
                    onTap: _ouvrirGoogleMaps,
                    nuit: nuit,
                  ),
              ],
            ),
          ),

          // ─── Badge de vitesse ───
          if (_navigationDemarree)
            Positioned(
              left: 12,
              bottom: _hauteurPanneau + 40 + basSecurite,
              child: AnimatedContainer(
                duration: duree,
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _vitesseKmh > 80 ? Colors.red : panneau,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _vitesseKmh > 80 ? Colors.white : CouleursTaama.indigo.withValues(alpha: 0.15),
                    width: 3,
                  ),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                // Rond de taille fixe : le texte rétrécit si la police est
                // agrandie, au lieu de déborder du cercle.
                padding: const EdgeInsets.all(8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${_vitesseKmh.round()}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        height: 1,
                        color: _vitesseKmh > 80 ? Colors.white : texte,
                      ),
                    ),
                    Text(
                      'km/h',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _vitesseKmh > 80 ? Colors.white70 : Colors.grey,
                      ),
                    ),
                  ],
                ),
                ),
              ),
            ),

          // ─── Panneau bas ───
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _panneauBas(nuit: nuit, panneau: panneau, texte: texte, duree: duree),
          ),

          // ─── Chargement ───
          if (_chargement)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: CouleursTaama.terreCuite),
                        SizedBox(height: 16),
                        Text('Calcul de l\'itinéraire...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panneauBas({
    required bool nuit,
    required Color panneau,
    required Color texte,
    required Duration duree,
  }) {
    final secondaire = nuit ? CouleursTaama.nuitTexteSecondaire : Colors.grey.shade600;
    final peutClientABord =
        !_jambeVersDestination && _positionDestinationReelle != null;

    return Container(
      decoration: BoxDecoration(
        color: panneau,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Chiffre(
                    valeur: _dureeMinutes != null ? '$_dureeMinutes' : '—',
                    unite: 'min',
                    couleur: CouleursTaama.terreCuite,
                    secondaire: secondaire,
                  ),
                  _separateur(secondaire),
                  _Chiffre(
                    valeur: _distanceKm != null ? _distanceKm!.toStringAsFixed(1) : '—',
                    unite: 'km',
                    couleur: texte,
                    secondaire: secondaire,
                  ),
                  _separateur(secondaire),
                  _Chiffre(
                    valeur: _heureArrivee,
                    unite: 'arrivée',
                    couleur: texte,
                    secondaire: secondaire,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: duree,
                child: !_navigationDemarree
                    // Hauteurs MINIMALES (pas fixes) et textes sur une ligne :
                    // avec une police agrandie, les boutons grandissent au
                    // lieu de déborder.
                    ? SizedBox(
                        key: const ValueKey('demarrer'),
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _chargement ? null : _demarrerNavigation,
                          icon: const Icon(Icons.navigation_rounded),
                          label: const Text(
                            'Démarrer la navigation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CouleursTaama.terreCuite,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(56),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      )
                    : Row(
                        key: ValueKey('actions_$_jambeVersDestination'),
                        children: [
                          OutlinedButton(
                            onPressed: _quitter,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(90, 56),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              foregroundColor: secondaire,
                              side: BorderSide(color: secondaire.withValues(alpha: 0.5)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text('Quitter', maxLines: 1),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _actionEnCours
                                  ? null
                                  : (peutClientABord ? _clientABordManuel : _proposerFinDeCourse),
                              icon: Icon(peutClientABord
                                  ? Icons.person_add_alt_1_rounded
                                  : Icons.flag_rounded),
                              label: Text(
                                peutClientABord ? 'Client à bord' : 'Terminer la course',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: peutClientABord
                                    ? CouleursTaama.indigo
                                    : CouleursTaama.terreCuite,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 56),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _separateur(Color couleur) => Container(
        width: 1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: couleur.withValues(alpha: 0.25),
      );
}

// ─── Widgets ───

class _Chiffre extends StatelessWidget {
  const _Chiffre({
    required this.valeur,
    required this.unite,
    required this.couleur,
    required this.secondaire,
  });

  final String valeur;
  final String unite;
  final Color couleur;
  final Color secondaire;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
            child: Text(
              valeur,
              key: ValueKey(valeur),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: couleur,
              ),
            ),
          ),
          Text(
            unite,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secondaire),
          ),
        ],
      ),
    );
  }
}

class _BoutonRond extends StatelessWidget {
  const _BoutonRond({
    required this.icone,
    required this.info,
    required this.onTap,
    required this.nuit,
    this.accent = false,
  });

  final IconData icone;
  final String info;
  final VoidCallback onTap;
  final bool nuit;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fond = accent
        ? CouleursTaama.terreCuite
        : (nuit ? CouleursTaama.nuitPanneau : Colors.white);
    final couleurIcone = accent
        ? Colors.white
        : (nuit ? CouleursTaama.blanc : CouleursTaama.indigo);
    return Material(
      color: fond,
      shape: const CircleBorder(),
      elevation: 5,
      shadowColor: Colors.black38,
      child: IconButton(
        tooltip: info,
        onPressed: onTap,
        icon: Icon(icone, color: couleurIcone),
        constraints: const BoxConstraints.tightFor(width: 50, height: 50),
      ),
    );
  }
}

/// Carte du haut : phase de la course (vers le client / vers la destination).
class _CartePhase extends StatelessWidget {
  const _CartePhase({
    required this.versDestination,
    required this.destination,
    required this.nbArrets,
    required this.nuit,
  });

  final bool versDestination;
  final String destination;
  final int nbArrets;
  final bool nuit;

  @override
  Widget build(BuildContext context) {
    final fond = nuit ? CouleursTaama.nuitPanneau : Colors.white;
    final texte = nuit ? CouleursTaama.blanc : CouleursTaama.indigo;
    final couleurPhase = versDestination ? CouleursTaama.terreCuite : CouleursTaama.indigo;
    return Container(
      // Hauteur minimale, pas fixe : police agrandie -> la carte grandit.
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: couleurPhase,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              versDestination ? 'Course' : 'Prise en charge',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              versDestination ? destination : 'Va chercher le client',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: texte),
            ),
          ),
          if (versDestination && nbArrets > 0) ...[
            const Icon(Icons.flag_rounded, size: 16, color: CouleursTaama.or),
            const SizedBox(width: 2),
            Text(
              '$nbArrets',
              style: const TextStyle(
                color: CouleursTaama.or,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Prochaine manœuvre, en grand (lisible d'un coup d'œil en roulant).
class _BandeauManoeuvre extends StatelessWidget {
  const _BandeauManoeuvre({
    super.key,
    required this.icone,
    required this.instruction,
    required this.distance,
  });

  final IconData icone;
  final String instruction;
  final String? distance;

  @override
  Widget build(BuildContext context) {
    final texte = instruction.isEmpty
        ? ''
        : instruction[0].toUpperCase() + instruction.substring(1);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CouleursTaama.indigo,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icone, color: Colors.white, size: 36),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (distance != null)
                  Text(
                    distance!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                Text(
                  texte,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau d'alerte. Sans action (les deux paramètres), aucun bouton.
class _BandeauAlerte extends StatelessWidget {
  const _BandeauAlerte({required this.texte, this.libelleAction, this.onAction});
  final String texte;
  final String? libelleAction;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.shade800,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          if (libelleAction != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                libelleAction!,
                maxLines: 1,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Point d'arrivée de la jambe en cours (client ou destination), avec une
/// onde qui pulse (fixe si animations réduites).
class _MarqueurCible extends StatefulWidget {
  const _MarqueurCible({required this.icone});
  final IconData icone;

  @override
  State<_MarqueurCible> createState() => _MarqueurCibleState();
}

class _MarqueurCibleState extends State<_MarqueurCible>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c
        ..stop()
        ..value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: (1 - t) * 0.6,
              child: Container(
                width: 34 + 36 * t,
                height: 34 + 36 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CouleursTaama.terreCuite.withValues(alpha: 0.2),
                  border: Border.all(color: CouleursTaama.terreCuite, width: 2),
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: CouleursTaama.terreCuite,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
        ),
        child: Icon(widget.icone, color: Colors.white, size: 22),
      ),
    );
  }
}