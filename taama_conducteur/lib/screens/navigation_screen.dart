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
import '../theme/couleurs_taama.dart';
import '../services/location_service.dart';
import '../services/api_service.dart';

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

  const _EtapeNavigation({required this.position, required this.instruction});
}

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

  const EcranNavigation({
    super.key,
    required this.demandeId,
    required this.destination,
    this.positionClient,
    this.telephoneClient,
    this.destinationLat,
    this.destinationLng,
    this.arrets = const [],
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

  LatLng? get _positionDestinationReelle {
    if (widget.destinationLat == null || widget.destinationLng == null) return null;
    return LatLng(widget.destinationLat!, widget.destinationLng!);
  }

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Future<void> _initialiser() async {
    // 1. Vérifie les permissions GPS
    final permission = await _verifierPermissions();
    if (!permission) {
      setState(() => _chargement = false);
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

    // 3. Utilise la position client fournie ou celle du backend
    _positionClient = widget.positionClient ??
        await _recupererPositionClient();

    // 4. Calcule l'itinéraire via OSRM
    if (_positionConducteur != null && _positionClient != null) {
      await _calculerItineraire();
    }

    setState(() => _chargement = false);

    // 5. Centre la carte sur les deux points
    _centrerCarte();
  }

  Future<bool> _verifierPermissions() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<LatLng?> _recupererPositionClient() async {
    try {
      // Géocode la destination via Nominatim (OpenStreetMap - gratuit)
      final destination = Uri.encodeComponent(
        '${widget.destination}, Bamako, Mali'
      );
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=$destination&format=json&limit=1'
      );

      final reponse = await http.get(url, headers: {
        'User-Agent': 'TaamaApp/1.0',
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

    // Fallback : centre de Bamako
    return const LatLng(12.6392, -8.0029);
  }

  /// Ne recalcule l'itinéraire que si le conducteur s'est écarté de plus de
  /// 50m de la route tracée — évite de spammer OSRM à chaque tick de 3s.
  bool _estHorsItineraire() {
    if (_itineraire.isEmpty || _positionConducteur == null) return false;
    const Distance distance = Distance();
    // Trouve le point le plus proche sur l'itinéraire
    double distanceMin = double.infinity;
    for (final point in _itineraire) {
      final d = distance(_positionConducteur!, point);
      if (d < distanceMin) distanceMin = d;
    }
    return distanceMin > 50; // Recalcule si > 50 mètres de l'itinéraire
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

  Future<void> _calculerItineraire() async {
    if (_positionConducteur == null || _positionClient == null) return;

    try {
      // Arrêts intermédiaires uniquement sur la 2e jambe (client à bord) —
      // avant ça, ils n'ont pas encore de sens pour l'itinéraire du
      // conducteur (qui va simplement chercher le client).
      final pointsVia = _jambeVersDestination ? widget.arrets : const [];

      // OSRM : API de routage open source, gratuite et sans clé API.
      // steps=true pour récupérer les instructions de navigation (virages,
      // etc.) — fonctionne nativement avec plus de 2 points (legs multiples,
      // déjà gérés par le expand() plus bas, qui aplati tous les legs).
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

          // Extrait les instructions de virage de chaque étape OSRM
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
            ));
          }

          setState(() {
            _itineraire = points;
            _distanceKm = distanceMetres / 1000;
            _dureeMinutes = (dureeSec / 60).ceil();
            _etapes = nouvellesEtapes;
            _etapeIndex = 0;
            _etapeAnnoncee = false;
          });
        }
      }
    } catch (e) {
      debugPrint('[Navigation] Erreur calcul itinéraire OSRM : $e');
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
      _etapeIndex++;
      _etapeAnnoncee = false;
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
    });

    await _calculerItineraire();
    _centrerCarte();
  }

  void _proposerFinDeCourse() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vous êtes arrivé !'),
        content: const Text('Souhaitez-vous terminer la course maintenant ?'),
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

  Future<void> _appelerClient() async {
    final numero = widget.telephoneClient;
    if (numero == null || numero.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: numero));
    } catch (e) {
      debugPrint('[Navigation] Erreur appel client : $e');
    }
  }

  void _centrerCarte() {
    if (_positionConducteur == null && _positionClient == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (_positionConducteur != null && _positionClient != null) {
        // Calcule le centre entre les deux points
        final lat = (_positionConducteur!.latitude +
                     _positionClient!.latitude) / 2;
        final lng = (_positionConducteur!.longitude +
                     _positionClient!.longitude) / 2;
        _mapController.move(LatLng(lat, lng), 13.0);
      } else {
        _mapController.move(
          _positionConducteur ?? _positionClient!,
          14.0,
        );
      }
    });
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
    setState(() => _navigationDemarree = true);

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
      });

      // Réutilise cette même position pour le client — pas de 2e requête
      // GPS séparée pour ça.
      _locationService.envoyerPosition(position.latitude, position.longitude);

      // Ne recalcule l'itinéraire que si on s'est écarté de la route
      if (_estHorsItineraire()) {
        await _calculerItineraire();
      }

      await _verifierInstructionVocale();
      await _verifierArrivee();

      // Centre la carte sur la position du conducteur
      _mapController.move(nouvellePosition, 15.0);
    }, onError: (e) {
      debugPrint('[Navigation] Erreur flux position : $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Carte plein écran
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _positionConducteur ??
                  const LatLng(12.6392, -8.0029),
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.taama.taama_conducteur',
                errorTileCallback: (tile, error, stack) {},
              ),

              // Itinéraire tracé en bleu
              if (_itineraire.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _itineraire,
                      color: CouleursTaama.indigo,
                      strokeWidth: 5.0,
                    ),
                  ],
                ),

              // Marqueurs
              MarkerLayer(
                markers: [
                  // Position conducteur (voiture)
                  if (_positionConducteur != null)
                    Marker(
                      point: _positionConducteur!,
                      width: 48,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: CouleursTaama.indigo,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: CouleursTaama.indigo
                                  .withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.directions_car,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),

                  // Position client (destination)
                  if (_positionClient != null)
                    Marker(
                      point: _positionClient!,
                      width: 48,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: CouleursTaama.terreCuite,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: CouleursTaama.terreCuite
                                  .withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person_pin_circle,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),

                  // Arrêts intermédiaires (2e jambe uniquement, voir
                  // _calculerItineraire) : petits marqueurs numérotés.
                  if (_jambeVersDestination)
                    for (var i = 0; i < widget.arrets.length; i++)
                      Marker(
                        point: LatLng(
                          widget.arrets[i]['latitude'] as double,
                          widget.arrets[i]['longitude'] as double,
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
                ],
              ),
            ],
          ),

          // Header flottant avec infos
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _jambeVersDestination
                                ? widget.destination
                                : 'Récupération du client',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: CouleursTaama.indigo,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.telephoneClient != null && widget.telephoneClient!.isNotEmpty)
                          IconButton(
                            onPressed: _appelerClient,
                            icon: const Icon(Icons.phone, color: CouleursTaama.terreCuite),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                    if (_distanceKm != null && _dureeMinutes != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.route,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            '${_distanceKm!.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Icon(Icons.access_time,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            '$_dureeMinutes min',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                          if (_jambeVersDestination && widget.arrets.isNotEmpty) ...[
                            const SizedBox(width: 16),
                            const Icon(Icons.flag,
                                size: 16, color: CouleursTaama.or),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.arrets.length} arrêt${widget.arrets.length > 1 ? 's' : ''}',
                              style: const TextStyle(
                                color: CouleursTaama.or,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Badge de vitesse actuelle
          if (_navigationDemarree)
            Positioned(
              bottom: 110,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _vitesseKmh > 80 ? Colors.red : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 6),
                  ],
                ),
                child: Text(
                  '${_vitesseKmh.round()} km/h',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _vitesseKmh > 80 ? Colors.white : CouleursTaama.indigo,
                  ),
                ),
              ),
            ),

          // Indicateur de chargement
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
                        CircularProgressIndicator(
                          color: CouleursTaama.terreCuite,
                        ),
                        SizedBox(height: 16),
                        Text('Calcul de l\'itinéraire...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Panel bas : bouton navigation
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: _navigationDemarree
                    ? Row(
                        children: [
                          const Icon(Icons.navigation,
                              color: CouleursTaama.indigo),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Navigation en cours...',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: CouleursTaama.indigo,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              _locationService.arreter();
                              _positionStream?.cancel();
                              Navigator.pop(context);
                            },
                            child: const Text(
                              'Terminer',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      )
                    : ElevatedButton.icon(
                        onPressed: _chargement ? null : _demarrerNavigation,
                        icon: const Icon(Icons.navigation),
                        label: const Text(
                          'Démarrer la navigation',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CouleursTaama.terreCuite,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 54),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
