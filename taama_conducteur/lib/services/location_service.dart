import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'api_service.dart';
import '../config/api_config.dart';

/// Vrai si l'écran de l'app est affiché. Android 12+ refuse de démarrer un
/// service au premier plan depuis l'arrière-plan : toute relance du suivi GPS
/// attend le retour de l'app à l'écran.
bool appVisible() {
  final etat = WidgetsBinding.instance.lifecycleState;
  return etat == null ||
      etat == AppLifecycleState.resumed ||
      etat == AppLifecycleState.inactive;
}

class LocationService {
  static final String _wsBaseUrl = ApiConfig.wsUrl;
  static const Duration _timeoutConnexion = Duration(seconds: 10);
  // Distance minimale (mètres) avant qu'une nouvelle position ne soit
  // poussée au serveur, tant que le conducteur est en ligne sans course
  // active — évite de spammer l'API si le conducteur est immobile.
  static const int _distanceFiltreEnLigne = 25;
  // Au plus cet intervalle entre deux envois, même à l'arrêt. Sans ça, un
  // conducteur immobile (feu rouge, embouteillage, en attente d'une course)
  // sort de la fenêtre de fraîcheur backend (45 s) après quelques dizaines de
  // secondes et devient invisible/inattribuable alors qu'il est bien en ligne.
  // Sur Android, chaque envoi correspond à une vraie mesure GPS ; le Timer de
  // répétition ne sert plus que sur iOS (voir demarrerSuiviPositionEnLigne).
  static const Duration _intervalleHeartbeat = Duration(seconds: 15);
  // Au-delà, plus aucune mesure GPS nouvelle : on n'envoie plus rien. Le
  // serveur sort alors le chauffeur des candidats, plutôt que de le croire
  // présent à un endroit périmé.
  static const Duration _ageMaxMesure = Duration(seconds: 30);
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
  // Flux GPS continu (pas un Timer) pendant une course — protégé par un
  // service en foreground (Android) / indicateur arrière-plan (iOS) via
  // _parametresPositionArrierePlan(), pour continuer à envoyer la position
  // même écran verrouillé/app en arrière-plan.
  StreamSubscription<Position>? _streamPositionEnvoi;
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
  Position? _derniereEnvoyee;
  DateTime? _dernierEnvoiLe;
  // Âge d'une mesure : depuis que son horodatage a changé, sur l'horloge du
  // téléphone. Jamais horloge du téléphone contre heure du GPS : sur un
  // téléphone mal réglé, le chauffeur ne serait plus jamais envoyé.
  DateTime? _horodatageDerniereMesure;
  DateTime? _mesureRecueLe;
  bool _enLigne = false;

  // Canal WebSocket d'une course : même logique, seuil de déplacement plus fin.
  double? _derniereLatWs;
  double? _derniereLngWs;
  DateTime? _dernierEnvoiWsLe;

  bool get connecte => _connecte;
  bool get enLigne => _enLigne;

  /// Réglages Android de TOUS les suivis GPS du chauffeur (en ligne, course,
  /// navigation, livraison). geolocator n'ouvre qu'un seul flux par app : tant
  /// qu'il existe, un nouvel appel le renvoie et ignore les réglages passés.
  /// Des réglages différents donneraient donc un comportement dépendant de
  /// l'écran ouvert en premier — y compris aucun service au premier plan.
  ///
  /// distanceFilter 0 + intervalle : une vraie mesure toutes les 5 s, même à
  /// l'arrêt. L'icône est référencée par l'icône de l'app : elle survit à la
  /// réduction des ressources de la release (sans icône valide, Android refuse
  /// la notification du service et l'app plante).
  static AndroidSettings parametresPositionAndroid() => AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Taama Conducteur',
          notificationText: 'Votre position est partagée tant que vous êtes en ligne ou en course.',
          notificationChannelName: 'Position du chauffeur',
          notificationIcon: AndroidResource(name: 'ic_launcher_foreground', defType: 'drawable'),
          setOngoing: true,
          enableWakeLock: true,
        ),
      );

  /// Cette position part-elle vers le serveur ? Non si la mesure n'est plus
  /// nouvelle ; sinon au premier envoi, après [_intervalleHeartbeat], ou dès
  /// [metresMin] de déplacement (au plus un envoi par
  /// [_intervalleMinimumEntreEnvois], throttle backend : 30/min).
  static bool doitEnvoyerPosition({
    required Duration ageMesure,
    required Duration? depuisDernierEnvoi,
    required double? metresParcourus,
    double metresMin = 25,
  }) {
    if (ageMesure > _ageMaxMesure) return false;
    if (depuisDernierEnvoi == null) return true;
    if (depuisDernierEnvoi >= _intervalleHeartbeat) return true;
    return metresParcourus != null &&
        metresParcourus >= metresMin &&
        depuisDernierEnvoi >= _intervalleMinimumEntreEnvois;
  }

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
  ///
  /// Autorisation « pendant l'utilisation » seulement : le suivi d'une course
  /// passe par un service au premier plan (voir _parametresPositionArrierePlan),
  /// qui garde l'accès à la position écran verrouillé. Jamais « Toujours ».
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

      return permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever;
    } catch (e) {
      debugPrint('[LocationService] Erreur vérification permissions : $e');
      return false;
    }
  }

  /// Paramètres de flux GPS pendant une course active : service en
  /// foreground (Android, notification persistante obligatoire pour que le
  /// suivi survive écran verrouillé) ou indicateur arrière-plan (iOS).
  LocationSettings _parametresPositionArrierePlan() {
    const distanceFiltre = 10; // mètres — assez fin pour un véhicule, sans spammer à l'arrêt
    if (defaultTargetPlatform == TargetPlatform.android) {
      return parametresPositionAndroid();
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

  /// Côté CONDUCTEUR : démarre l'envoi de position GPS pendant une course —
  /// flux continu (pas un polling toutes les 3s) protégé par un service en
  /// foreground, pour continuer même écran verrouillé/app en arrière-plan.
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

    _streamPositionEnvoi = Geolocator.getPositionStream(
      locationSettings: _parametresPositionArrierePlan(),
    ).listen(
      (position) => envoyerPosition(position.latitude, position.longitude),
      onError: (e) => debugPrint('[LocationService] Erreur flux envoi : $e'),
    );
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

    // Le flux émet toutes les 5 s, même à l'arrêt : pas d'envoi au client ni de
    // calcul d'itinéraire de son côté tant que le chauffeur ne bouge pas.
    final maintenant = DateTime.now();
    final precedentLat = _derniereLatWs;
    final precedentLng = _derniereLngWs;
    final dernierEnvoi = _dernierEnvoiWsLe;
    if (!doitEnvoyerPosition(
      ageMesure: Duration.zero,
      depuisDernierEnvoi: dernierEnvoi == null ? null : maintenant.difference(dernierEnvoi),
      metresParcourus: precedentLat == null || precedentLng == null
          ? null
          : Geolocator.distanceBetween(precedentLat, precedentLng, lat, lng),
      metresMin: 10,
    )) {
      return;
    }
    _derniereLatWs = lat;
    _derniereLngWs = lng;
    _dernierEnvoiWsLe = maintenant;
    _channel?.sink.add(jsonEncode({'lat': lat, 'lng': lng}));
  }

  /// Côté CONDUCTEUR : démarre le suivi GPS "en ligne" (indépendant d'une
  /// course précise) — position immédiate puis flux continu poussé via
  /// POST /chauffeur/position/. Actif tant que le conducteur est disponible,
  /// qu'il ait une course en cours ou non. Sur Android, protégé par un service
  /// au premier plan : continue écran verrouillé.
  Future<void> demarrerSuiviPositionEnLigne() async {
    if (_enLigne) return; // Déjà démarré

    // Relancé au retour à l'écran (_resynchroniserDisponibilite).
    if (!appVisible()) return;

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

    final android = defaultTargetPlatform == TargetPlatform.android;
    _streamPositionEnLigne = Geolocator.getPositionStream(
      locationSettings: android
          ? parametresPositionAndroid()
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: _distanceFiltreEnLigne,
            ),
    ).listen(
      _pousserPosition,
      onError: (e) {
        // GPS coupé, permission retirée... Le flux est mort : on libère le
        // verrou pour que _resynchroniserDisponibilite relance le suivi.
        debugPrint('[LocationService] Erreur flux position : $e');
        _suiviEnLigneInterrompu();
      },
    );

    // iOS seulement : le flux ne se déclenche que sur un déplacement, on répète
    // la dernière position pour rester frais à l'arrêt. Sur Android, le flux
    // émet déjà toutes les 5 s : sans GPS, plus rien n'est envoyé.
    if (!android) {
      _timerHeartbeat = Timer.periodic(_intervalleHeartbeat, (_) {
        final derniere = _dernierePosition;
        if (derniere != null) _pousserPosition(derniere, repetition: true);
      });
    }
  }

  void _suiviEnLigneInterrompu() {
    _streamPositionEnLigne?.cancel();
    _streamPositionEnLigne = null;
    _timerHeartbeat?.cancel();
    _timerHeartbeat = null;
    _oublierMesures();
    _enLigne = false;
  }

  void _oublierMesures() {
    _dernierePosition = null;
    _derniereEnvoyee = null;
    _dernierEnvoiLe = null;
    _horodatageDerniereMesure = null;
    _mesureRecueLe = null;
  }

  Future<void> _pousserPosition(Position position, {bool repetition = false}) async {
    _dernierePosition = position;

    final maintenant = DateTime.now();
    if (position.timestamp != _horodatageDerniereMesure) {
      _horodatageDerniereMesure = position.timestamp;
      _mesureRecueLe = maintenant;
    }

    final precedente = _derniereEnvoyee;
    final dernierEnvoi = _dernierEnvoiLe;
    if (!doitEnvoyerPosition(
      ageMesure: repetition ? Duration.zero : maintenant.difference(_mesureRecueLe!),
      depuisDernierEnvoi: dernierEnvoi == null ? null : maintenant.difference(dernierEnvoi),
      metresParcourus: precedente == null
          ? null
          : Geolocator.distanceBetween(
              precedente.latitude, precedente.longitude, position.latitude, position.longitude,
            ),
    )) {
      return;
    }
    _derniereEnvoyee = position;
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
    _oublierMesures();
    if (!_enLigne) return;
    _enLigne = false;

    try {
      await ApiService.deconnexionChauffeur();
    } catch (e) {
      debugPrint('[LocationService] Erreur déconnexion : $e');
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
      // _streamPositionEnvoi (s'il existe, mode demarrerEnvoiPosition) n'a
      // jamais été annulé : il reprend l'envoi sur ce nouveau _channel dès
      // son prochain évènement GPS. Rien à faire ici pour connecterPourEnvoi
      // (l'appelant pousse lui-même via envoyerPosition()).
    }
  }

  /// Arrête proprement l'envoi/écoute et ferme le WebSocket.
  void arreter() {
    _arrete = true;
    _timerReconnexion?.cancel();
    _timerReconnexion = null;
    _streamPositionEnvoi?.cancel();
    _streamPositionEnvoi = null;
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