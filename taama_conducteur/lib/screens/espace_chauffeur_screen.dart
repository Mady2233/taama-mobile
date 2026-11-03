// DESIGN_V4_CARTE
//
// Accueil chauffeur, style « carte en fond » : la carte occupe tout l'écran
// avec la position du chauffeur, un grand bouton En ligne / Hors ligne, et
// une feuille du bas (glissable) qui contient stats, demandes et livraisons.
//
// TOUTE la logique métier est reprise à l'identique de la version
// précédente (GPS continu par demande, canal « disponibilite », détection de
// nouvelle demande, resynchronisation, workarounds de mise en page). Seul
// ajout : lecture de la position GPS (Geolocator) pour CENTRER la carte —
// elle n'est envoyée nulle part, l'envoi reste géré par LocationService.

import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../carte/fond_carte.dart';
import '../services/annulations_course.dart';
import '../services/api_service.dart';
import '../services/config_app.dart';
import '../services/demande_entrante_navigator.dart';
import '../services/location_service.dart';
import '../services/polling_premier_plan.dart';
import '../services/sonnerie_service.dart';
import '../theme/couleurs_taama.dart';
import '../utils/format.dart';
import '../widgets/couche_carte_taama.dart';
import '../widgets/widget_avatar_conducteur.dart';
import 'connexion_screen.dart';
import 'profil_chauffeur_screen.dart';
import 'portefeuille_screen.dart';
import 'chat_screen.dart';
import 'mes_conversations_screen.dart';
import 'verification_conducteur_screen.dart';
import 'navigation_screen.dart';
import 'avis_app_screen.dart';
import 'courier_livreur_screen.dart';
import 'inscription_chauffeur_screen.dart';
import '../widgets/widget_annulation.dart';

const LatLng _centreBamako = LatLng(12.6392, -8.0029);

class EcranEspaceChauffeur extends StatefulWidget {
  const EcranEspaceChauffeur({super.key});

  @override
  State<EcranEspaceChauffeur> createState() => _EcranEspaceChauffeurState();
}

class _EcranEspaceChauffeurState extends State<EcranEspaceChauffeur>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _profil;
  List<dynamic> _demandesAssignees = [];
  List<dynamic> _livraisonsCourier = [];
  int? _solde;
  // Écran affiché seulement. Écran verrouillé, le service de position garde
  // l'app active : ce polling tournerait sans fin (~2 000 requêtes/h). Les
  // demandes arrivent alors par notification push.
  late final PollingPremierPlan _polling = PollingPremierPlan(
    intervalle: const Duration(seconds: 5),
    action: _rafraichirTout,
  );
  static const String _cleExplicationPosition = 'explication_position_en_ligne_vue';
  bool _explicationOuverte = false;
  bool _explicationRefusee = false;
  bool _chargementInitial = true;
  int? _enTraitement;

  // États explicites de l'accueil (jamais un écran vide sans message).
  String? _erreurProfil; // chargement du profil en échec -> « Réessayer »
  bool _sansProfil = false; // 403 : compte sans profil chauffeur
  String? _erreurDemandes; // dernier rafraîchissement des demandes en échec

  // Une position GPS est envoyée en continu pour chaque demande "en route"
  final Map<int, LocationService> _servicesLocalisation = {};

  // Position GPS envoyée en continu tant que le conducteur est "disponible",
  // même sans course en cours (canal général "disponibilite").
  final LocationService _serviceLocalisationGenerale = LocationService();

  // ─── Carte (affichage uniquement) ───
  final MapController _carte = MapController();
  bool _cartePrete = false;
  LatLng? _positionChauffeur;
  bool _basculeEnCours = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConfigApp.paiementActif.addListener(_surChangementPaiement);
    _chargerProfil();
    _chargerSolde();
    _rafraichirTout();
    _localiser();
    _polling.demarrer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    switch (etat) {
      case AppLifecycleState.resumed:
        _polling.reprendre();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _polling.suspendre();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ConfigApp.paiementActif.removeListener(_surChangementPaiement);
    _polling.suspendre();
    for (final service in _servicesLocalisation.values) {
      service.arreter();
    }
    _serviceLocalisationGenerale.arreterSuiviPositionEnLigne();
    _carte.dispose();
    SonnerieService.instance.arreter();
    super.dispose();
  }

  // ─── Position pour la carte (lecture seule) ───

  Future<void> _localiser() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      final point = LatLng(p.latitude, p.longitude);
      setState(() => _positionChauffeur = point);
      if (_cartePrete) _carte.move(point, 15.5);
    } catch (e) {
      if (kDebugMode) debugPrint('[Carte] Position indisponible : $e');
    }
  }

  /// Bascule avec retour visuel (bouton occupé) — délègue entièrement à
  /// _basculerDisponibilite, inchangée.
  Future<void> _surToggle() async {
    if (_basculeEnCours) return;
    setState(() => _basculeEnCours = true);
    try {
      await _basculerDisponibilite();
    } finally {
      if (mounted) setState(() => _basculeEnCours = false);
    }
    _localiser();
  }

  /// Démarre l'envoi de la position GPS pour chaque demande qui vient de
  /// passer "en route", et l'arrête pour celles qui ne le sont plus
  /// (terminées, annulées, ou disparues de la liste des demandes assignées).
  ///
  /// Appelée à CHAQUE tick de _rafraichirTout, quoi qu'il arrive par
  /// ailleurs (voir _rafraichirTout) — try/catch défensif avec un tag de log
  /// distinct : une régression ici (ex. cast id invalide) ne doit jamais
  /// passer inaperçue, mais ne doit pas non plus empêcher le prochain tick.
  void _synchroniserSuiviPosition() {
    try {
      final idsEnRoute = _demandesAssignees
          .where(
            (d) => d['statut'] == 'en_route' || d['statut'] == 'client_a_bord',
          )
          .map((d) => d['id'] as int)
          .toSet();

      for (final id in idsEnRoute) {
        // Hors écran, le service de position ne peut pas démarrer : au retour.
        if (!_servicesLocalisation.containsKey(id) && appVisible()) {
          final service = LocationService();
          service.demarrerEnvoiPosition('$id');
          _servicesLocalisation[id] = service;
        }
      }

      final idsATerminer = _servicesLocalisation.keys
          .where((id) => !idsEnRoute.contains(id))
          .toList();
      for (final id in idsATerminer) {
        _servicesLocalisation.remove(id)?.arreter();
      }
    } catch (e) {
      debugPrint('[SuiviPosition] Erreur synchronisation : $e');
    }
  }

  Future<void> _chargerProfil() async {
    try {
      final profil = await ApiService.monProfilChauffeur();
      if (!mounted) return;
      setState(() {
        _profil = profil;
        _erreurProfil = null;
        _sansProfil = false;
      });
      if (profil['disponible'] == true) {
        // Déjà en ligne (ex: relance de l'app) : on reprend le suivi GPS.
        _demarrerSuiviEnLigne();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sansProfil = e.statusCode == 403;
        _erreurProfil = _sansProfil ? null : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreurProfil = 'Pas de connexion. Vérifie ton réseau.');
    } finally {
      if (mounted) setState(() => _chargementInitial = false);
    }
  }

  Future<void> _reessayerChargement() async {
    setState(() {
      _chargementInitial = true;
      _erreurProfil = null;
    });
    await _chargerProfil();
    if (!mounted || _profil == null) return;
    await _chargerSolde();
    await _rafraichirTout();
  }

  /// Réponse du serveur sur le mode gratuit arrivée après l'ouverture.
  void _surChangementPaiement() {
    if (!mounted) return;
    setState(() {});
    _chargerSolde();
  }

  Future<void> _chargerSolde() async {
    // Mode gratuit : aucun solde affiché, donc aucune requête.
    if (!ConfigApp.paiementActif.value) return;
    try {
      final solde = await ApiService.monSolde();
      if (!mounted) return;
      setState(() => _solde = solde);
    } catch (e) {
      debugPrint('Erreur chargement solde : $e');
    }
  }

  /// Rafraîchit chaque source de façon INDÉPENDANTE : l'échec d'une (ex. un
  /// endpoint retiré, une erreur réseau ponctuelle) ne doit jamais empêcher
  /// les autres de s'exécuter. En particulier, le suivi GPS et la
  /// resynchronisation de la disponibilité sont critiques (un chauffeur qui
  /// arrête de pousser sa position ou de resynchroniser sa dispo devient
  /// invisible/incohérent sans que rien ne le signale) : ils tournent à
  /// CHAQUE tick, quoi qu'il arrive sur les autres sources ci-dessous.
  Future<void> _rafraichirTout() async {
    await Future.wait([
      _rafraichirDemandesAssignees(),
      _rafraichirLivraisonsCourier(),
    ]);

    // Dépend de _demandesAssignees, donc appelé après son rafraîchissement —
    // mais _rafraichirDemandesAssignees() ne relance jamais d'exception (try/
    // catch interne), donc ce point est toujours atteint.
    _synchroniserSuiviPosition();

    // Le serveur peut désormais faire basculer `disponible` tout seul
    // (acceptation/fin de course) — je resynchronise le toggle affiché
    // sans jamais toucher au suivi GPS (celui-ci ne dépend que de l'action
    // explicite du conducteur sur le toggle, pas de sa disponibilité).
    await _resynchroniserDisponibilite();
  }

  /// Une course en route qui disparaît de la liste a été annulée par le client :
  /// secours si le push n'est pas arrivé. L'écran de navigation fait le tri avec
  /// une fin de course lancée par le chauffeur lui-même.
  void _signalerCoursesDisparues(List<dynamic> demandes) {
    final presentes = demandes.map((d) => d['id']).toSet();
    for (final ancienne in _demandesAssignees) {
      if (ancienne['statut'] == 'en_route' && !presentes.contains(ancienne['id'])) {
        AnnulationsCourse.signaler(ancienne['id'] as int);
      }
    }
  }

  Future<void> _rafraichirDemandesAssignees() async {
    try {
      final demandes = await ApiService.mesDemandesAssignees();
      if (!mounted) return;
      _detecterNouvelleDemande(demandes);
      _signalerCoursesDisparues(demandes);
      setState(() {
        _demandesAssignees = demandes;
        _erreurDemandes = null;
      });
      // Plus aucune demande en attente de réponse (acceptée depuis l'écran
      // de demande entrante, expirée, reprise par le serveur…) : on coupe.
      if (!demandes.any((d) => d['statut'] == 'chauffeur_trouve')) {
        SonnerieService.instance.arreter();
      }
    } catch (e) {
      debugPrint('[DemandesAssignees] Erreur rafraîchissement : $e');
      if (mounted) {
        setState(() => _erreurDemandes = 'Impossible de mettre à jour tes demandes.');
      }
    }
  }

  /// Filet de secours fiable pour ouvrir l'écran de demande entrante : dès
  /// qu'une demande 'chauffeur_trouve' apparaît qui n'était pas connue au
  /// tick précédent, on l'affiche. Complète le déclenchement FCM (qui ne
  /// couvre que le tap sur la notification), pas besoin que l'app soit au
  /// premier plan sur CET écran précis — ce polling tourne dès que
  /// l'espace chauffeur est ouvert.
  void _detecterNouvelleDemande(List<dynamic> nouvellesDemandes) {
    final idsDejaConnus = _demandesAssignees.map((d) => d['id']).toSet();
    for (final demande in nouvellesDemandes) {
      final id = demande['id'];
      if (demande['statut'] == 'chauffeur_trouve' &&
          !idsDejaConnus.contains(id)) {
        // La sonnerie (boucle + vibration, 45 s max) est démarrée par
        // DemandeEntranteNavigator à l'ouverture de l'écran, et coupée à sa
        // fermeture : pas de sonnerie pour une demande déjà refusée.
        DemandeEntranteNavigator.afficherSiNecessaire(
          id as int,
          demandeInitiale: demande as Map<String, dynamic>,
        );
      }
    }
  }

  Future<void> _rafraichirLivraisonsCourier() async {
    try {
      final livraisons = await ApiService.mesLivraisonsCourier();
      if (!mounted) return;
      setState(() => _livraisonsCourier = livraisons);
    } catch (e) {
      debugPrint('[LivraisonsCourier] Erreur rafraîchissement : $e');
    }
  }

  Future<void> _resynchroniserDisponibilite() async {
    try {
      final profil = await ApiService.monProfilChauffeur();
      if (!mounted) return;
      setState(() {
        _profil?['disponible'] = profil['disponible'];
        // Photo changée sur l'écran Profil ou lors de la vérification : la
        // barre du haut suit sans requête de plus.
        _profil?['photo_profil'] = profil['photo_profil'];
      });

      // Garde-fou : si le serveur dit "disponible" mais que le suivi GPS
      // général n'est plus actif (stream mort en silence, exception
      // avalée...), on le relance. Un chauffeur "disponible mais invisible"
      // est pire qu'un chauffeur clairement hors ligne.
      if (profil['disponible'] == true &&
          !_serviceLocalisationGenerale.enLigne) {
        debugPrint(
          '[Disponibilite] Suivi GPS inactif alors que disponible=true — relance',
        );
        await _demarrerSuiviEnLigne();
      }
    } catch (e) {
      debugPrint('[Disponibilite] Erreur resynchronisation : $e');
    }
  }

  Future<void> _demarrerSuiviEnLigne() async {
    if (!await _explicationPositionVue()) return;
    await _serviceLocalisationGenerale.demarrerSuiviPositionEnLigne();
  }

  /// Avant la première collecte, écran verrouillé compris : le chauffeur sait
  /// ce qui se passe et peut rester hors ligne. Affichée une seule fois.
  Future<bool> _explicationPositionVue() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_cleExplicationPosition) == true) return true;
    if (_explicationOuverte || _explicationRefusee || !mounted) return false;

    _explicationOuverte = true;
    final accepte = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Votre position quand vous êtes en ligne'),
        content: const Text(
          'Tant que vous êtes en ligne, Taama utilise votre position, même écran '
          'verrouillé, pour vous proposer les courses proches et guider le client. '
          'Une notification reste affichée. Tout s’arrête quand vous passez hors ligne.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Pas maintenant'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
    _explicationOuverte = false;

    if (accepte == true) {
      await prefs.setBool(_cleExplicationPosition, true);
      return true;
    }

    // Refus alors que le serveur le croit en ligne : hors ligne, sinon il
    // resterait « disponible » sans position, et la question reviendrait
    // à chaque rafraîchissement.
    _explicationRefusee = true;
    if (_profil?['disponible'] == true) {
      try {
        final disponible = await ApiService.changerDisponibilite();
        if (mounted) setState(() => _profil?['disponible'] = disponible);
      } catch (e) {
        debugPrint('Erreur passage hors ligne : $e');
      }
    }
    return false;
  }

  Future<void> _basculerDisponibilite() async {
    try {
      if (_profil?['disponible'] != true) {
        _explicationRefusee = false; // Demande explicite du chauffeur.
        if (!await _explicationPositionVue()) return;
      }
      final nouvelleDisponibilite = await ApiService.changerDisponibilite();
      if (!mounted) return;
      setState(() => _profil?['disponible'] = nouvelleDisponibilite);

      if (nouvelleDisponibilite) {
        // Conducteur passe en ligne → démarre le suivi GPS
        await _serviceLocalisationGenerale.demarrerSuiviPositionEnLigne();
        debugPrint('[GPS] Suivi de position démarré');
      } else {
        // Conducteur passe hors ligne → arrête le suivi GPS
        await _serviceLocalisationGenerale.arreterSuiviPositionEnLigne();
        debugPrint('[GPS] Suivi de position arrêté');
      }
    } catch (e) {
      debugPrint('Erreur changement disponibilité : $e');
    }
  }

  Future<void> _accepterDemande(int id) async {
    SonnerieService.instance.arreter();
    setState(() => _enTraitement = id);
    try {
      await ApiService.accepterDemande(id);
      await _rafraichirTout();
    } catch (e) {
      _afficherErreur(e);
    } finally {
      if (mounted) setState(() => _enTraitement = null);
    }
  }

  Future<void> _refuserDemande(int id) async {
    SonnerieService.instance.arreter();
    setState(() => _enTraitement = id);
    try {
      await ApiService.refuserDemande(id);
      DemandeEntranteNavigator.marquerRefusee(id);
      await _rafraichirTout();
    } catch (e) {
      _afficherErreur(e);
    } finally {
      if (mounted) setState(() => _enTraitement = null);
    }
  }

  /// Message exact du serveur, ou « Pas de connexion » pour une erreur réseau.
  void _afficherErreur(Object e) {
    if (!mounted) return;
    final message = e is ApiException ? e.message : 'Pas de connexion. Vérifie ton réseau et réessaie.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _annulerCourse(Map<String, dynamic> demande) async {
    final demandeId = demande['id'] as int;
    // Sans information du serveur sur une course acceptée (ancien backend) : pas
    // de « gratuite » annoncée. Le serveur reste seul à décider.
    final resultat = await afficherDialogueAnnulation(
      context,
      secondesGratuites: (demande['annulation_gratuite_secondes'] as num?)?.toInt() ??
          (demande['statut'] == 'en_route' ? 0 : null),
      penaliteTardive: (demande['penalite_annulation_tardive'] as num?)?.toInt() ?? 0,
      estChauffeur: true,
    );
    if (resultat == null) return;

    try {
      final reponse = await ApiService.annulerDemandeChaufeur(
        demandeId,
        motif: resultat['motif'] as String,
      );

      final penalite = reponse['penalite'] as int? ?? 0;
      final avertissement = reponse['avertissement'] as String?;

      if (!mounted) return;

      if (avertissement != null) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text('Avertissement'),
              ],
            ),
            content: Text(avertissement),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Compris'),
              ),
            ],
          ),
        );
      } else if (penalite > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Course annulée. Pénalité : ${formaterFcfa(penalite)}'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      _rafraichirTout();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  void _deconnexion() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const EcranConnexion()),
      (route) => false,
    );
  }

  void _ouvrirChat({required String roomName, required String titre}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EcranChat(roomName: roomName, titreConversation: titre),
      ),
    );
  }

  void _ouvrir(Widget ecran) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ecran));
  }

  // ─── Construction ───

  @override
  Widget build(BuildContext context) {
    final disponible = _profil?['disponible'] as bool? ?? false;
    final hautSecurite = MediaQuery.paddingOf(context).top;
    // Attribution OSM/MapTiler en haut à gauche, sous la barre flottante :
    // la feuille du bas (qui monte et descend) ne la recouvre jamais.
    final margeAttribution = EdgeInsets.fromLTRB(8, hautSecurite + 76, 8, 8);

    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      body: Stack(
        children: [
          // 1. Carte plein écran
          Positioned.fill(
            child: FlutterMap(
              mapController: _carte,
              options: MapOptions(
                initialCenter: _positionChauffeur ?? _centreBamako,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: () {
                  _cartePrete = true;
                  final p = _positionChauffeur;
                  if (p != null) _carte.move(p, 15.5);
                },
              ),
              children: [
                const FondCarteTaama(),
                CoucheCarteTaama(
                  reserves: [
                    ZoneReservee.attribution(
                      alignement: Alignment.topLeft,
                      marge: margeAttribution,
                    ),
                  ],
                ),
                if (_positionChauffeur != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _positionChauffeur!,
                        width: 80,
                        height: 80,
                        child: _MarqueurChauffeur(enLigne: disponible),
                      ),
                    ],
                  ),
                AttributionCarteTaama(
                  alignement: Alignment.topLeft,
                  marge: margeAttribution,
                ),
              ],
            ),
          ),

          // 2. Barre flottante du haut
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: _barreHaute(disponible),
              ),
            ),
          ),

          // 3. Feuille du bas glissable
          DraggableScrollableSheet(
            initialChildSize: 0.46,
            minChildSize: 0.30,
            maxChildSize: 0.92,
            snap: true,
            snapSizes: const [0.46],
            builder: (context, controleur) => _feuille(controleur, disponible),
          ),
        ],
      ),
    );
  }

  Widget _barreHaute(bool disponible) {
    final nom = _profil?['nom']?.toString() ?? '';
    return Row(
      children: [
        Expanded(
          child: Container(
            // Hauteur minimale, pas fixe : avec une police agrandie, la
            // barre grandit au lieu de déborder.
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: _ombreFlottante,
            ),
            child: Row(
              children: [
                AvatarConducteur(
                  photoUrl: _profil?['photo_profil'] as String?,
                  nom: nom,
                  radius: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nom.isEmpty ? 'Taama Conducteur' : nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: CouleursTaama.indigo,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: disponible ? Colors.green : Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            disponible ? 'En ligne' : 'Hors ligne',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: disponible
                                  ? Colors.green.shade700
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        _BoutonRondBlanc(
          icone: Icons.chat_bubble_rounded,
          info: 'Messages',
          onTap: () => _ouvrir(const MesConversationsScreen()),
        ),
        const SizedBox(width: 8),
        _menu(),
      ],
    );
  }

  Widget _menu() {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black26,
      child: PopupMenuButton<String>(
        tooltip: 'Menu',
        icon: const Icon(Icons.menu_rounded, color: CouleursTaama.indigo),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (choix) {
          switch (choix) {
            case 'profil':
              _ouvrir(const EcranProfilChauffeur());
            case 'portefeuille':
              _ouvrir(const EcranPortefeuille(estChauffeur: true));
            case 'verification':
              _ouvrir(const EcranVerificationConducteur());
            case 'avis':
              _ouvrir(const EcranAvisApp());
            case 'deconnexion':
              _deconnexion();
          }
        },
        itemBuilder: (context) => [
          _entreeMenu('profil', Icons.person_rounded, 'Mon profil'),
          if (ConfigApp.paiementActif.value)
            _entreeMenu('portefeuille', Icons.account_balance_wallet_rounded,
                'Mon portefeuille'),
          _entreeMenu('verification', Icons.verified_user_rounded, 'Vérification'),
          _entreeMenu('avis', Icons.star_rounded, 'Donner mon avis'),
          const PopupMenuDivider(),
          _entreeMenu('deconnexion', Icons.logout_rounded, 'Déconnexion',
              danger: true),
        ],
      ),
    );
  }

  PopupMenuItem<String> _entreeMenu(String valeur, IconData icone, String texte,
      {bool danger = false}) {
    final couleur = danger ? Colors.red : CouleursTaama.indigo;
    return PopupMenuItem<String>(
      value: valeur,
      child: Row(
        children: [
          Icon(icone, size: 20, color: couleur),
          const SizedBox(width: 12),
          Text(texte,
              style: TextStyle(
                  color: danger ? Colors.red : null, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _feuille(ScrollController controleur, bool disponible) {
    return Container(
      decoration: const BoxDecoration(
        color: CouleursTaama.sable,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: CouleursTaama.ombre, blurRadius: 24, offset: Offset(0, -6)),
        ],
      ),
      child: _chargementInitial
          ? ListView(
              controller: controleur,
              children: const [
                SizedBox(height: 60),
                Center(
                  child: CircularProgressIndicator(color: CouleursTaama.terreCuite),
                ),
              ],
            )
          : RefreshIndicator(
              color: CouleursTaama.terreCuite,
              onRefresh: () async {
                await _chargerProfil();
                await _chargerSolde();
                await _rafraichirTout();
                await _localiser();
              },
              child: ListView(
                controller: controleur,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 0. États sans profil chargé : jamais un écran vide.
                  if (_sansProfil)
                    _CarteEtat(
                      icone: Icons.person_add_alt_1,
                      titre: "Ton compte n'a pas encore de profil chauffeur",
                      texte: 'Crée-le pour commencer à recevoir des courses.',
                      libelleAction: 'Créer mon profil',
                      onAction: () => Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const EcranInscriptionChauffeur()),
                        (route) => false,
                      ),
                    )
                  else if (_profil == null)
                    _CarteEtat(
                      icone: Icons.wifi_off,
                      titre: 'Impossible de charger ton profil',
                      texte: _erreurProfil ?? 'Une erreur est survenue.',
                      libelleAction: 'Réessayer',
                      onAction: _reessayerChargement,
                    ),

                  // 1. Gros bouton En ligne / Hors ligne
                  if (_profil != null) ...[
                    _BoutonDisponibilite(
                      disponible: disponible,
                      enCours: _basculeEnCours,
                      onTap: _surToggle,
                    ),
                    const SizedBox(height: 12),
                    _BandeauProfil(profil: _profil!),
                    const SizedBox(height: 16),
                  ],

                  // 2. Stats rapides
                  if (_profil != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _CarteStat(
                            icone: Icons.directions_car_filled_rounded,
                            couleur: CouleursTaama.terreCuite,
                            valeur: '${_demandesAssignees.length}',
                            libelle: 'Courses du jour',
                          ),
                        ),
                        // Mode gratuit (lu sur le serveur) : pas de solde.
                        if (ConfigApp.paiementActif.value) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CarteStat(
                              icone: Icons.account_balance_wallet_rounded,
                              couleur: CouleursTaama.indigo,
                              valeur: _solde != null ? formaterFcfa(_solde!) : '...',
                              libelle: 'Solde',
                            ),
                          ),
                        ],
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CarteStat(
                            icone: Icons.star_rounded,
                            couleur: CouleursTaama.or,
                            valeur: (_profil!['note'] as num?)?.toStringAsFixed(1) ?? '—',
                            libelle: 'Note',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                  ],

                  // 2.5 Rafraîchissement en échec.
                  if (_profil != null && _erreurDemandes != null) ...[
                    _CarteEtat(
                      icone: Icons.sync_problem,
                      titre: _erreurDemandes!,
                      texte: _demandesAssignees.isEmpty
                          ? 'Vérifie ton réseau.'
                          : 'Les demandes affichées ne sont peut-être plus à jour.',
                      libelleAction: 'Réessayer',
                      onAction: _rafraichirTout,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 3. Demandes en cours
                  if (_profil != null) ...[
                    const _TitreSection(
                      icone: Icons.local_taxi_rounded,
                      texte: 'Demandes en cours',
                    ),
                    const SizedBox(height: 12),
                    if (_demandesAssignees.isEmpty && _erreurDemandes == null)
                      disponible
                          ? const _AttenteRadar()
                          : const _CarteEtat(
                              icone: Icons.power_settings_new_rounded,
                              titre: 'Tu es hors ligne',
                              texte: 'Passe en ligne pour recevoir des demandes.',
                            ),
                    ..._demandesAssignees.map((demande) {
                      final enAttente = demande['statut'] == 'chauffeur_trouve';
                      final demandeId = demande['id'] as int;
                      // Clé incluant enAttente (pas juste l'id) : force un
                      // remontage complet du sous-arbre quand le statut
                      // bascule 'chauffeur_trouve' -> 'en_route' (la Row
                      // change de structure : 3 boutons Expanded vs.
                      // Expanded+boutons fixes). Sans ça, Flutter tente de
                      // réutiliser en place l'ancien arbre de rendu, ce qui
                      // provoquait "BoxConstraints forces an infinite
                      // width" en cascade (jusqu'à un écran blanc) au
                      // moment précis de l'acceptation d'une course.
                      // La clé est sur l'enveloppe animée (le parent).
                      return _ApparitionCarte(
                        key: ValueKey('${demandeId}_$enAttente'),
                        enAttente: enAttente,
                        child: _CarteDemande(
                          key: ValueKey('carte_${demandeId}_$enAttente'),
                          demande: demande,
                          enAttente: enAttente,
                          enTraitement: _enTraitement == demande['id'],
                          onRefuser: () => _refuserDemande(demande['id'] as int),
                          onAccepter: () =>
                              _accepterDemande(demande['id'] as int),
                          onChat: () => _ouvrirChat(
                            roomName: 'demande_${demande['id']}',
                            titre: 'Client - ${demande['destination']}',
                          ),
                          onAnnuler: () => _annulerCourse(demande as Map<String, dynamic>),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                  ],

                  // 3.5 Livraisons Courier en cours
                  if (_livraisonsCourier.isNotEmpty) ...[
                    const _TitreSection(
                      icone: Icons.inventory_2_rounded,
                      texte: 'Livraisons en cours',
                    ),
                    const SizedBox(height: 12),
                    ..._livraisonsCourier.map((livraison) {
                      return _CarteLivraisonCourier(
                        livraison: livraison,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EcranCourierLivreur(
                                livraison: livraison as Map<String, dynamic>,
                              ),
                            ),
                          );
                          if (mounted) await _rafraichirTout();
                        },
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}

// ─── Widgets ───

const List<BoxShadow> _ombreCarte = [
  BoxShadow(color: CouleursTaama.ombreLegere, blurRadius: 12, offset: Offset(0, 4)),
];

const List<BoxShadow> _ombreFlottante = [
  BoxShadow(color: CouleursTaama.ombre, blurRadius: 16, offset: Offset(0, 6)),
];

class _BoutonRondBlanc extends StatelessWidget {
  const _BoutonRondBlanc({required this.icone, required this.info, required this.onTap});
  final IconData icone;
  final String info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black26,
      child: IconButton(
        tooltip: info,
        onPressed: onTap,
        icon: Icon(icone, color: CouleursTaama.indigo),
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }
}

/// Position du chauffeur sur la carte : pastille véhicule + halo qui pulse
/// quand il est en ligne (fixe s'il est hors ligne ou animations réduites).
class _MarqueurChauffeur extends StatefulWidget {
  const _MarqueurChauffeur({required this.enLigne});
  final bool enLigne;

  @override
  State<_MarqueurChauffeur> createState() => _MarqueurChauffeurState();
}

class _MarqueurChauffeurState extends State<_MarqueurChauffeur>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mettreAJour();
  }

  @override
  void didUpdateWidget(covariant _MarqueurChauffeur ancien) {
    super.didUpdateWidget(ancien);
    _mettreAJour();
  }

  void _mettreAJour() {
    final anime = widget.enLigne && !MediaQuery.disableAnimationsOf(context);
    if (anime && !_c.isAnimating) {
      _c.repeat();
    } else if (!anime) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couleur = widget.enLigne ? CouleursTaama.terreCuite : Colors.grey.shade600;
    return Semantics(
      label: 'Ma position',
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.enLigne)
                Opacity(
                  opacity: (1 - t) * 0.6,
                  child: Container(
                    width: 30 + 50 * t,
                    height: 30 + 50 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: couleur.withValues(alpha: 0.18),
                      border: Border.all(color: couleur, width: 2),
                    ),
                  ),
                ),
              child!,
            ],
          );
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: couleur,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: _ombreFlottante,
          ),
          child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// Grand bouton de disponibilité, l'élément principal de l'écran.
/// Animations : couleur qui glisse d'un état à l'autre, texte qui change en
/// fondu, léger enfoncement au toucher, et halo qui « respire » en ligne.
class _BoutonDisponibilite extends StatefulWidget {
  const _BoutonDisponibilite({
    required this.disponible,
    required this.enCours,
    required this.onTap,
  });

  final bool disponible;
  final bool enCours;
  final VoidCallback onTap;

  @override
  State<_BoutonDisponibilite> createState() => _BoutonDisponibiliteState();
}

class _BoutonDisponibiliteState extends State<_BoutonDisponibilite>
    with SingleTickerProviderStateMixin {
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  bool _appuye = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mettreAJour();
  }

  @override
  void didUpdateWidget(covariant _BoutonDisponibilite ancien) {
    super.didUpdateWidget(ancien);
    _mettreAJour();
  }

  void _mettreAJour() {
    final anime = widget.disponible && !MediaQuery.disableAnimationsOf(context);
    if (anime) {
      if (!_halo.isAnimating) _halo.repeat(reverse: true);
    } else {
      _halo
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disponible = widget.disponible;
    final fond = disponible ? CouleursTaama.indigo : CouleursTaama.terreCuite;
    final reduit = MediaQuery.disableAnimationsOf(context);
    final duree = reduit ? Duration.zero : const Duration(milliseconds: 380);

    final contenu = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.enCours ? null : widget.onTap,
        onHighlightChanged: (v) => setState(() => _appuye = v),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: AnimatedSwitcher(
                  duration: duree,
                  transitionBuilder: (enfant, animation) =>
                      ScaleTransition(scale: animation, child: enfant),
                  child: widget.enCours
                      ? const Padding(
                          key: ValueKey('chargement'),
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : Icon(
                          disponible
                              ? Icons.wifi_tethering_rounded
                              : Icons.power_settings_new_rounded,
                          key: ValueKey('icone_$disponible'),
                          color: Colors.white,
                          size: 24,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AnimatedSwitcher(
                  duration: duree,
                  transitionBuilder: (enfant, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.25),
                        end: Offset.zero,
                      ).animate(animation),
                      child: enfant,
                    ),
                  ),
                  child: Column(
                    key: ValueKey('texte_$disponible'),
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        disponible ? 'Tu es en ligne' : 'Passer en ligne',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        disponible
                            ? 'Appuie pour te mettre en pause'
                            : 'Appuie pour recevoir des courses',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _halo,
      child: contenu,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_halo.value);
        return AnimatedScale(
          scale: _appuye ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: duree,
            curve: Curves.easeOutCubic,
            // Hauteur MINIMALE, pas fixe : avec une police agrandie (réglage
            // Android), le contenu fait grandir le bouton au lieu de déborder.
            constraints: const BoxConstraints(minHeight: 68),
            decoration: BoxDecoration(
              color: fond,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: fond.withValues(alpha: 0.35 + 0.25 * t),
                  blurRadius: 14 + 14 * t,
                  spreadRadius: 2 * t,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// En ligne sans course : radar animé (ondes qui partent du centre).
class _AttenteRadar extends StatefulWidget {
  const _AttenteRadar();

  @override
  State<_AttenteRadar> createState() => _AttenteRadarState();
}

class _AttenteRadarState extends State<_AttenteRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c
        ..stop()
        ..value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _onde(double t) {
    return Opacity(
      opacity: (1 - t) * 0.7,
      child: Container(
        width: 30 + 66 * t,
        height: 30 + 66 * t,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: CouleursTaama.terreCuite, width: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      decoration: BoxDecoration(
        color: CouleursTaama.blanc,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _ombreCarte,
      ),
      child: Column(
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) => Stack(
                alignment: Alignment.center,
                children: [
                  _onde(_c.value),
                  _onde((_c.value + 0.33) % 1),
                  _onde((_c.value + 0.66) % 1),
                  child!,
                ],
              ),
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: CouleursTaama.terreCuite,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.radar_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'En attente de courses…',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: CouleursTaama.indigo,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Les demandes proches apparaîtront ici.',
            textAlign: TextAlign.center,
            style: TextStyle(color: CouleursTaama.grisTexte),
          ),
        ],
      ),
    );
  }
}

/// Entrée d'une carte de demande : glisse et apparaît ; si elle attend une
/// réponse (nouvelle demande), elle « bat » doucement pour attirer l'œil.
class _ApparitionCarte extends StatefulWidget {
  const _ApparitionCarte({super.key, required this.enAttente, required this.child});

  final bool enAttente;
  final Widget child;

  @override
  State<_ApparitionCarte> createState() => _ApparitionCarteState();
}

class _ApparitionCarteState extends State<_ApparitionCarte>
    with TickerProviderStateMixin {
  late final AnimationController _entree = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final AnimationController _battement = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _initialise = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduit = MediaQuery.disableAnimationsOf(context);
    if (!_initialise) {
      _initialise = true;
      if (reduit) {
        _entree.value = 1;
      } else {
        _entree.forward();
      }
    }
    if (widget.enAttente && !reduit) {
      if (!_battement.isAnimating) _battement.repeat(reverse: true);
    } else {
      _battement
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _entree.dispose();
    _battement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_entree, _battement]),
      child: widget.child,
      builder: (context, child) {
        final e = Curves.easeOutCubic.transform(_entree.value);
        final b = Curves.easeInOut.transform(_battement.value);
        return Opacity(
          opacity: e,
          child: Transform.translate(
            offset: Offset(0, (1 - e) * 24),
            child: Transform.scale(scale: 1 + 0.015 * b, child: child),
          ),
        );
      },
    );
  }
}

/// Valeur de stat qui monte en compteur (entier ou décimal, ex. la note).
/// Texte non numérique (« ... », « — ») : affiché tel quel.
class _ValeurAnimee extends StatelessWidget {
  const _ValeurAnimee({required this.valeur});
  final String valeur;

  static const TextStyle _style = TextStyle(fontWeight: FontWeight.w800, fontSize: 17);

  @override
  Widget build(BuildContext context) {
    final entier = int.tryParse(valeur);
    final decimal = entier == null ? double.tryParse(valeur) : null;
    if (entier == null && decimal == null) {
      // Un montant ne se coupe pas : il rétrécit pour tenir dans sa carte.
      return FittedBox(fit: BoxFit.scaleDown, child: Text(valeur, style: _style));
    }

    final cible = (entier ?? decimal)!.toDouble();
    final duree = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 700);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: cible),
      duration: duree,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        entier != null ? v.round().toString() : v.toStringAsFixed(1),
        style: _style,
      ),
    );
  }
}

/// Véhicule, note et vérification du chauffeur (sous le gros bouton).
class _BandeauProfil extends StatelessWidget {
  const _BandeauProfil({required this.profil});
  final Map<String, dynamic> profil;

  /// « Toyota Corolla • AB1234 », sans jamais afficher « null ».
  String get _ligneVehicule => [profil['vehicule'], profil['plaque']]
      .map((v) => v?.toString().trim() ?? '')
      .where((v) => v.isNotEmpty && v != 'null')
      .join(' • ');

  Widget _badgeVerification(BuildContext context) {
    final verifie = profil['verifie'] as bool? ?? false;
    final statut = profil['statut_verification']?.toString() ?? 'non_soumis';

    late Color couleur;
    late IconData icone;
    late String libelle;

    if (verifie) {
      couleur = Colors.green;
      icone = Icons.check_circle;
      libelle = 'Vérifié';
    } else if (statut == 'en_attente') {
      couleur = CouleursTaama.or;
      icone = Icons.hourglass_top;
      libelle = 'En attente';
    } else {
      couleur = Colors.red;
      icone = Icons.cancel;
      libelle = 'Non vérifié';
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const EcranVerificationConducteur(),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: couleur, size: 14),
            const SizedBox(width: 4),
            Text(
              libelle,
              style: TextStyle(color: couleur, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _ombreCarte,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_car_filled_rounded,
                  color: CouleursTaama.indigo, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _ligneVehicule.isEmpty ? 'Véhicule non renseigné' : _ligneVehicule,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _ligneVehicule.isEmpty ? Colors.grey.shade600 : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _badgeVerification(context),
            ],
          ),
          // Le serveur ne propose aucune course à un compte non vérifié.
          if (profil['verifie'] != true) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EcranVerificationConducteur(),
                ),
              ),
              child: const Text(
                'Vous recevrez des courses une fois votre compte vérifié.',
                style: TextStyle(fontSize: 12, color: CouleursTaama.grisTexte),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Titre de section (icône + texte).
class _TitreSection extends StatelessWidget {
  const _TitreSection({required this.icone, required this.texte});
  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 18, color: CouleursTaama.indigo),
        const SizedBox(width: 6),
        Text(
          texte,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: CouleursTaama.indigo,
          ),
        ),
      ],
    );
  }
}

/// Carte d'état (erreur, compte sans profil, aucune demande).
class _CarteEtat extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String texte;
  final String? libelleAction;
  final VoidCallback? onAction;

  const _CarteEtat({
    required this.icone,
    required this.titre,
    required this.texte,
    this.libelleAction,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CouleursTaama.blanc,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _ombreCarte,
      ),
      child: Column(
        children: [
          Icon(icone, size: 36, color: CouleursTaama.grisTexte),
          const SizedBox(height: 10),
          Text(
            titre,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: CouleursTaama.indigo,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            texte,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CouleursTaama.grisTexte),
          ),
          if (libelleAction != null && onAction != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(backgroundColor: CouleursTaama.terreCuite),
              child: Text(libelleAction!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Une des cartes de statistiques rapides (courses du jour, solde, note).
class _CarteStat extends StatelessWidget {
  final IconData icone;
  final Color couleur;
  final String valeur;
  final String libelle;

  const _CarteStat({
    required this.icone,
    required this.couleur,
    required this.valeur,
    required this.libelle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _ombreCarte,
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icone, color: couleur, size: 20),
          ),
          const SizedBox(height: 8),
          _ValeurAnimee(valeur: valeur),
          const SizedBox(height: 2),
          Text(
            libelle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton icône dans une Row : largeur minimale finie (voir _CarteDemande).
const Size _tailleBoutonIcone = Size(48, 44);

/// Une carte de demande instantanée assignée au conducteur.
class _CarteDemande extends StatelessWidget {
  final dynamic demande;
  final bool enAttente;
  final bool enTraitement;
  final VoidCallback onRefuser;
  final VoidCallback onAccepter;
  final VoidCallback onChat;
  final VoidCallback onAnnuler;

  const _CarteDemande({
    super.key,
    required this.demande,
    required this.enAttente,
    required this.enTraitement,
    required this.onRefuser,
    required this.onAccepter,
    required this.onChat,
    required this.onAnnuler,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: _ombreCarte,
        border: enAttente
            ? Border.all(color: CouleursTaama.terreCuite, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (enAttente) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: CouleursTaama.terreCuite,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Nouvelle demande',
                style: TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: CouleursTaama.terreCuite.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: CouleursTaama.terreCuite, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      demande['destination']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${demande['type_transport']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Text(
                formaterFcfaApi(demande['prix_estime']) ?? '',
                style: const TextStyle(
                  color: CouleursTaama.terreCuite,
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (enAttente)
            Row(
              children: [
                // Marges réduites (le thème met 24 px de chaque côté) et
                // texte sur une ligne : sur un écran de 360 px, « Accepter »
                // se coupait au milieu du mot.
                Expanded(
                  child: OutlinedButton(
                    onPressed: enTraitement ? null : onRefuser,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      'Refuser',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: enTraitement ? null : onAccepter,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: enTraitement
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Accepter',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                // Largeur FINIE : le thème impose une largeur minimale
                // infinie, impossible hors Expanded. 52 px de haut, comme
                // Refuser et Accepter.
                OutlinedButton(
                  onPressed: onChat,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(52, 52),
                    padding: EdgeInsets.zero,
                    foregroundColor: CouleursTaama.indigo,
                    side: const BorderSide(color: CouleursTaama.indigo),
                  ),
                  child: const Icon(Icons.chat_bubble_outline, size: 18),
                ),
              ],
            )
          else
            // Les deux boutons icône ont une largeur minimale FINIE
            // (_tailleBoutonIcone) : le thème de l'app (main.dart) impose
            // minimumSize: Size.fromHeight(52), soit une largeur minimale
            // infinie, impossible à placer dans cette Row de taille libre
            // ("BoxConstraints forces an infinite width") — la carte entière
            // ne se dessinait plus, et « Demandes en cours » restait vide.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'En route',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: onChat,
                      style: OutlinedButton.styleFrom(
                        minimumSize: _tailleBoutonIcone,
                        foregroundColor: CouleursTaama.indigo,
                        side: const BorderSide(color: CouleursTaama.indigo),
                      ),
                      child: const Icon(Icons.chat_bubble_outline, size: 18),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: onAnnuler,
                      style: OutlinedButton.styleFrom(
                        minimumSize: _tailleBoutonIcone,
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Icon(Icons.cancel_outlined, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          // 'en_route' (vers le client) ou 'client_a_bord' (vers sa
          // destination) : avant acceptation, ni la navigation ni le
          // téléphone du client n'ont à être exposés au conducteur.
          if (demande['statut'] == 'en_route' ||
              demande['statut'] == 'client_a_bord') ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) {
                      // depart_lat/depart_lng : vraie position de prise en
                      // charge du client, déjà dans la réponse API. Sans ça,
                      // EcranNavigation géocode le texte `destination` (où le
                      // client VEUT ALLER) et affiche ce point comme position
                      // du client — bug corrigé ici.
                      final departLat = (demande['depart_lat'] as num?)
                          ?.toDouble();
                      final departLng = (demande['depart_lng'] as num?)
                          ?.toDouble();
                      final destinationLat = (demande['destination_lat'] as num?)
                          ?.toDouble();
                      final destinationLng = (demande['destination_lng'] as num?)
                          ?.toDouble();
                      // Si le client est déjà à bord (écran de navigation
                      // rouvert après l'avoir quitté), on route directement
                      // vers la destination — pas de 2e jambe à redéclencher,
                      // le passage en 'client_a_bord' a déjà eu lieu côté
                      // backend.
                      final clientDejaABord =
                          demande['statut'] == 'client_a_bord';
                      final positionClient = clientDejaABord
                          ? (destinationLat != null && destinationLng != null
                                ? LatLng(destinationLat, destinationLng)
                                : null)
                          : (departLat != null && departLng != null
                                ? LatLng(departLat, departLng)
                                : null);
                      return EcranNavigation(
                        demandeId: demande['id'] is int
                            ? demande['id'] as int
                            : int.tryParse(demande['id'].toString()) ?? 0,
                        destination: demande['destination']?.toString() ?? '',
                        positionClient: positionClient,
                        destinationLat: clientDejaABord ? null : destinationLat,
                        destinationLng: clientDejaABord ? null : destinationLng,
                        telephoneClient: demande['client_telephone']?.toString(),
                        arrets: extraireArrets(demande['arrets']),
                        clientDejaABord: clientDejaABord,
                      );
                    },
                  ),
                ),
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Naviguer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CouleursTaama.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Une carte de livraison Courier assignée au conducteur, en cours.
class _CarteLivraisonCourier extends StatelessWidget {
  final dynamic livraison;
  final VoidCallback onTap;

  const _CarteLivraisonCourier({required this.livraison, required this.onTap});

  static const _iconesCategorie = {
    'colis': Icons.inventory_2_rounded,
    'repas': Icons.restaurant_rounded,
    'document': Icons.description_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final icone = _iconesCategorie[livraison['categorie']] ?? Icons.inventory_2_rounded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 2,
        shadowColor: Colors.black12,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: CouleursTaama.terreCuite.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icone, color: CouleursTaama.terreCuite, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        livraison['description_colis']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${livraison['adresse_collecte']} → ${livraison['adresse_livraison']}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formaterFcfaApi(livraison['prix']) ?? '',
                        style: const TextStyle(
                          color: CouleursTaama.terreCuite,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}