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
  // Reconnexion : backoff exponentiel plafonné — récupère vite sur un simple
  // blip réseau, sans marteler le serveur si la coupure dure.
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

  bool get connecte => _connecte;

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