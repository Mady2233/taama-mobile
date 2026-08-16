import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import '../config/api_config.dart';

class LocationService {
  static final String _wsBaseUrl = ApiConfig.wsUrl;
  static const Duration _intervalleEnvoi = Duration(seconds: 3);
  static const Duration _timeoutConnexion = Duration(seconds: 10);
  // Distance minimale (mètres) avant qu'une nouvelle position ne soit
  // poussée au serveur, tant que le conducteur est en ligne sans course
  // active — évite de spammer l'API si le conducteur est immobile.
  static const int _distanceFiltreEnLigne = 25;
  // Heartbeat temporel : repousse la DERNIÈRE position connue même si le
  // conducteur n'a pas bougé de _distanceFiltreEnLigne. Sans ça, un
  // conducteur immobile (feu rouge, embouteillage, en attente d'une course)
  // sort de la fenêtre de fraîcheur backend après quelques dizaines de
  // secondes et devient invisible/inattribuable alors qu'il est bien en ligne.
  static const Duration _intervalleHeartbeat = Duration(seconds: 15);
  // Gate anti-rafale : mouvement (distanceFilter) et heartbeat peuvent se
  // déclencher quasi simultanément ; au plus un envoi réseau toutes les 4s,
  // pour rester largement sous le throttle backend (30/min).
  static const Duration _intervalleMinimumEntreEnvois = Duration(seconds: 4);
  // Reconnexion (canal WS par-course) : backoff exponentiel plafonné —
  // récupère vite sur un simple blip réseau, sans marteler le serveur si
  // la coupure dure. Sans rapport avec le suivi REST "en ligne" ci-dessus,
  // qui gère déjà ses erreurs de flux indépendamment.
  static const Duration _delaiReconnexionInitial = Duration(seconds: 2);
  static const Duration _delaiReconnexionMax = Duration(seconds: 20);

  WebSocketChannel? _channel;
  StreamSubscription? _streamSubscription;
  Timer? _timerEnvoi;
  Timer? _timerReconnexion;
  bool _connecte = false;
  // true tant qu'aucun suivi n'est en cours, ou après arreter() — distinct de
  // `_connecte` : entre deux tentatives de reconnexion, on n'est pas connecté
  // mais on n'est pas non plus "arrêté", il ne faut pas abandonner.
  bool _arrete = true;
  Duration _delaiReconnexion = _delaiReconnexionInitial;

  // Mémorisés pour pouvoir relancer exactement le même suivi après une
  // reconnexion (le stream d'un WebSocket fermé n'est jamais réutilisable).
  String? _demandeIdActive;
  void Function(double lat, double lng)? _callbackPositionActif;

  // Suivi REST (indépendant du WebSocket ci-dessus) : actif tant que le
  // conducteur est "en ligne" (disponible=true), qu'il ait une course en
  // cours ou non.
  StreamSubscription<Position>? _streamPositionEnLigne;
  Timer? _timerHeartbeat;
  Position? _dernierePosition;
  DateTime? _dernierEnvoiLe;
  bool _enLigne = false;

  bool get connecte => _connecte;
  bool get enLigne => _enLigne;

  /// Établit la connexion WebSocket avec timeout et gestion d'erreur.
  Future<bool> _connecter(String demandeId) async {
    final token = ApiService.token;
    if (token == null) {
      debugPrint('[LocationService] Token manquant — connexion annulée');
      return false;
    }

    try {
      final uri = Uri.parse(
        '$_wsBaseUrl/ws/location/$demandeId/?token=$token',
      );
      _channel = WebSocketChannel.connect(uri);
      
      // Attendre que la connexion soit établie avec timeout
      await _channel!.ready.timeout(
        _timeoutConnexion,
        onTimeout: () => throw TimeoutException('WebSocket timeout'),
      );
      
      _connecte = true;
      debugPrint('[LocationService] WebSocket connecté pour demande $demandeId');
      return true;
    } catch (e) {
      debugPrint('[LocationService] Erreur connexion WebSocket : $e');
      _channel = null;
      _connecte = false;
      return false;
    }
  }

  /// Vérifie et demande les permissions GPS.
  Future<bool> _verifierPermissions() async {
    try {
      final servicesActifs = await Geolocator.isLocationServiceEnabled();
      if (!servicesActifs) {
        debugPrint('[LocationService] Service GPS désactivé');
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('[LocationService] Permission GPS refusée');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[LocationService] Erreur vérification permissions : $e');
      return false;
    }
  }

  /// Côté CONDUCTEUR : démarre l'envoi de position GPS toutes les 3s.
  Future<void> demarrerEnvoiPosition(String demandeId) async {
    if (!_arrete) return; // Déjà démarré (ou reconnexion en cours)

    final permissionsOk = await _verifierPermissions();
    if (!permissionsOk) return;

    _arrete = false;
    _demandeIdActive = demandeId;
    _callbackPositionActif = null; // mode envoi : rien à réécouter après reconnexion
    _delaiReconnexion = _delaiReconnexionInitial;

    final connexionOk = await _connecter(demandeId);
    if (!connexionOk) {
      _planifierReconnexion();
      return;
    }
    _ecouterEtatConnexion();

    // Envoie immédiatement la position actuelle, sans attendre le 1er tick
    await _envoyerPositionActuelle();

    _timerEnvoi = Timer.periodic(_intervalleEnvoi, (_) => _envoyerPositionActuelle());
  }

  /// Établit uniquement la connexion WebSocket d'envoi, SANS démarrer de
  /// boucle GPS interne (pas de _timerEnvoi) — pour un appelant qui gère
  /// déjà sa propre boucle de position (ex. EcranNavigation, qui interroge
  /// le GPS pour sa carte/son itinéraire) et veut réutiliser cette même
  /// position via envoyerPosition() au lieu de refaire un 2e appel GPS.
  Future<bool> connecterPourEnvoi(String demandeId) async {
    if (!_arrete) return _connecte; // Déjà démarré (ou reconnexion en cours)

    final permissionsOk = await _verifierPermissions();
    if (!permissionsOk) return false;

    _arrete = false;
    _demandeIdActive = demandeId;
    _callbackPositionActif = null;
    _delaiReconnexion = _delaiReconnexionInitial;

    final connexionOk = await _connecter(demandeId);
    if (!connexionOk) {
      _planifierReconnexion();
      return false;
    }
    _ecouterEtatConnexion();
    return true;
  }

  /// Envoie une position déjà obtenue par l'appelant — aucun appel GPS ici,
  /// contrairement à _envoyerPositionActuelle(). À utiliser après
  /// connecterPourEnvoi(), jamais après demarrerEnvoiPosition() (qui gère
  /// déjà son propre envoi périodique).
  void envoyerPosition(double lat, double lng) {
    if (!_connecte || _channel == null) return;
    _channel?.sink.add(jsonEncode({'lat': lat, 'lng': lng}));
  }

  /// Côté CONDUCTEUR : démarre le suivi GPS "en ligne" (indépendant d'une
  /// course précise) — position immédiate puis flux continu (distanceFilter
  /// ~25m) poussé via POST /chauffeur/position/. Actif tant que le
  /// conducteur est disponible, qu'il ait une course en cours ou non.
  Future<void> demarrerSuiviPositionEnLigne() async {
    if (_enLigne) return; // Déjà démarré

    // Posé de façon SYNCHRONE, avant le premier await : verrou immédiat
    // contre un déclenchement concurrent (ex. deux ticks de
    // _resynchroniserDisponibilite qui se chevauchent si _verifierPermissions
    // met plus de 5s, l'intervalle du polling). Sans ça, les deux appels
    // verraient _enLigne encore à false et démarreraient chacun leur propre
    // stream + timer, avec fuite de celui écrasé sans jamais être annulé.
    _enLigne = true;

    final permissionsOk = await _verifierPermissions();
    if (!permissionsOk) {
      _enLigne = false; // Rien n'a été démarré : on libère le verrou.
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      await _pousserPosition(position);
    } on TimeoutException {
      debugPrint('[LocationService] Timeout GPS initial — on continue avec le flux');
    } catch (e) {
      debugPrint('[LocationService] Erreur position initiale : $e');
    }

    _streamPositionEnLigne = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFiltreEnLigne,
      ),
    ).listen(
      _pousserPosition,
      onError: (e) => debugPrint('[LocationService] Erreur flux position : $e'),
    );

    // Heartbeat : repousse la dernière position connue même à l'arrêt
    // complet (le stream ci-dessus ne se déclenche que sur un déplacement).
    _timerHeartbeat = Timer.periodic(_intervalleHeartbeat, (_) {
      final derniere = _dernierePosition;
      if (derniere != null) _pousserPosition(derniere);
    });
  }

  Future<void> _pousserPosition(Position position) async {
    _dernierePosition = position;

    // Gate anti-rafale : voir _intervalleMinimumEntreEnvois.
    final maintenant = DateTime.now();
    if (_dernierEnvoiLe != null &&
        maintenant.difference(_dernierEnvoiLe!) < _intervalleMinimumEntreEnvois) {
      return;
    }
    _dernierEnvoiLe = maintenant;

    try {
      await ApiService.envoyerPositionChauffeur(
        lat: position.latitude,
        lng: position.longitude,
      );
      debugPrint('[LocationService] Position poussée : ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('[LocationService] Erreur envoi position REST : $e');
    }
  }

  /// Arrête le suivi GPS "en ligne" et signale la déconnexion au serveur.
  /// Annule le stream ET le heartbeat — jamais de timer orphelin après
  /// passage hors ligne / logout.
  Future<void> arreterSuiviPositionEnLigne() async {
    await _streamPositionEnLigne?.cancel();
    _streamPositionEnLigne = null;
    _timerHeartbeat?.cancel();
    _timerHeartbeat = null;
    _dernierePosition = null;
    _dernierEnvoiLe = null;
    if (!_enLigne) return;
    _enLigne = false;

    try {
      await ApiService.deconnexionChauffeur();
    } catch (e) {
      debugPrint('[LocationService] Erreur déconnexion : $e');
    }
  }

  Future<void> _envoyerPositionActuelle() async {
    // Pas de _timerEnvoi?.cancel() ici : le timer doit continuer de tourner
    // pendant une reconnexion, pour reprendre l'envoi automatiquement dès
    // que _connecte redevient true — sinon plus rien n'est jamais renvoyé
    // après le premier blip réseau, même une fois reconnecté.
    if (!_connecte || _channel == null) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      final message = jsonEncode({
        'lat': position.latitude,
        'lng': position.longitude,
      });

      _channel?.sink.add(message);
      debugPrint('[LocationService] Position envoyée : ${position.latitude}, ${position.longitude}');
    } on TimeoutException {
      debugPrint('[LocationService] Timeout GPS — on réessaie au prochain tick');
    } catch (e) {
      debugPrint('[LocationService] Erreur envoi position : $e');
    }
  }

  /// Côté CLIENT : écoute les positions du conducteur en temps réel.
  Future<void> ecouterPosition(
    String demandeId,
    void Function(double lat, double lng) onPosition,
  ) async {
    if (!_arrete) return;

    _arrete = false;
    _demandeIdActive = demandeId;
    _callbackPositionActif = onPosition;
    _delaiReconnexion = _delaiReconnexionInitial;

    final connexionOk = await _connecter(demandeId);
    if (!connexionOk) {
      _planifierReconnexion();
      return;
    }
    _ecouterPositionsEntrantes(onPosition);
  }

  void _ecouterPositionsEntrantes(void Function(double lat, double lng) onPosition) {
    _streamSubscription = _channel?.stream.listen(
      (data) {
        try {
          final message = jsonDecode(data?.toString() ?? '{}')
              as Map<String, dynamic>;

          final latRaw = message['lat'];
          final lngRaw = message['lng'];

          if (latRaw == null || lngRaw == null) return;

          final lat = (latRaw as num).toDouble();
          final lng = (lngRaw as num).toDouble();

          // Validation des coordonnées (Bamako : lat ~12.6, lng ~-8.0)
          if (lat.abs() > 90 || lng.abs() > 180) {
            debugPrint('[LocationService] Coordonnées invalides reçues');
            return;
          }

          onPosition(lat, lng);
        } catch (e) {
          debugPrint('[LocationService] Erreur parsing position : $e');
        }
      },
      onError: (e) {
        debugPrint('[LocationService] Erreur stream WebSocket : $e');
        _gererDeconnexion();
      },
      onDone: () {
        debugPrint('[LocationService] WebSocket fermé');
        _gererDeconnexion();
      },
    );
  }

  /// Écoute le canal côté CONDUCTEUR (envoi) — aucun message n'y est
  /// attendu, mais sans ce listener onError/onDone ne se déclenchent
  /// jamais : sink.add() sur un canal mort échoue silencieusement et rien
  /// ne détecte la coupure.
  void _ecouterEtatConnexion() {
    _streamSubscription = _channel?.stream.listen(
      (_) {},
      onError: (e) {
        debugPrint('[LocationService] Erreur canal envoi : $e');
        _gererDeconnexion();
      },
      onDone: () {
        debugPrint('[LocationService] Canal envoi fermé');
        _gererDeconnexion();
      },
    );
  }

  void _gererDeconnexion() {
    _connecte = false;
    if (_arrete) return; // arreter() appelé entre-temps : ne rien relancer.
    _planifierReconnexion();
  }

  void _planifierReconnexion() {
    _timerReconnexion?.cancel();
    debugPrint('[LocationService] Reconnexion dans ${_delaiReconnexion.inSeconds}s');
    _timerReconnexion = Timer(_delaiReconnexion, _tenterReconnexion);
    final prochainDelai = _delaiReconnexion.inSeconds * 2;
    _delaiReconnexion = Duration(
      seconds: prochainDelai > _delaiReconnexionMax.inSeconds
          ? _delaiReconnexionMax.inSeconds
          : prochainDelai,
    );
  }

  Future<void> _tenterReconnexion() async {
    if (_arrete || _demandeIdActive == null) return;

    _channel?.sink.close();
    final connexionOk = await _connecter(_demandeIdActive!);
    if (!connexionOk) {
      _planifierReconnexion();
      return;
    }

    _delaiReconnexion = _delaiReconnexionInitial; // succès : backoff réinitialisé
    debugPrint('[LocationService] Reconnecté');

    if (_callbackPositionActif != null) {
      _ecouterPositionsEntrantes(_callbackPositionActif!);
    } else {
      _ecouterEtatConnexion();
      // _timerEnvoi n'a jamais été annulé : il reprend l'envoi sur ce
      // nouveau _channel dès son prochain tick.
    }
  }

  /// Arrête proprement l'envoi/écoute et ferme le WebSocket.
  void arreter() {
    _arrete = true;
    _timerReconnexion?.cancel();
    _timerReconnexion = null;
    _timerEnvoi?.cancel();
    _timerEnvoi = null;
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _connecte = false;
    _demandeIdActive = null;
    _callbackPositionActif = null;
    debugPrint('[LocationService] Service arrêté proprement');
  }
}