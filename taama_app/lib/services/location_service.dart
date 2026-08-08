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

  WebSocketChannel? _channel;
  StreamSubscription? _streamSubscription;
  Timer? _timerEnvoi;
  bool _connecte = false;

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
    if (_connecte) return; // Déjà démarré

    final permissionsOk = await _verifierPermissions();
    if (!permissionsOk) return;

    final connexionOk = await _connecter(demandeId);
    if (!connexionOk) return;

    _timerEnvoi = Timer.periodic(_intervalleEnvoi, (_) async {
      if (!_connecte || _channel == null) {
        _timerEnvoi?.cancel();
        return;
      }

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
    });
  }

  /// Côté CLIENT : écoute les positions du conducteur en temps réel.
  Future<void> ecouterPosition(
    String demandeId,
    void Function(double lat, double lng) onPosition,
  ) async {
    if (_connecte) return;

    final connexionOk = await _connecter(demandeId);
    if (!connexionOk) return;

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
        _connecte = false;
      },
      onDone: () {
        debugPrint('[LocationService] WebSocket fermé');
        _connecte = false;
      },
    );
  }

  /// Arrête proprement l'envoi/écoute et ferme le WebSocket.
  void arreter() {
    _timerEnvoi?.cancel();
    _timerEnvoi = null;
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _connecte = false;
    debugPrint('[LocationService] Service arrêté proprement');
  }
}