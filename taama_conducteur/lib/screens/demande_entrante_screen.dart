// DESIGN_V4
//
// Écran « appel entrant » d'une nouvelle demande.
//
// Inchangé : vérification du statut (mesDemandesAssignees), compte à rebours
// de 30 s, expiration = refus best-effort, accepter → EcranNavigation
// (pushReplacement), ignorer avec gestion 400/404, _fermer() via pop(),
// PopScope pendant un traitement, messages d'erreur lisibles.
//
// Nouveau :
// - carte sombre plein écran (client + chauffeur, cadrée sur les deux,
//   plein nord) sous un dégradé ;
// - grand anneau de compte à rebours fluide qui passe du blanc à l'or puis
//   au rouge, avec vibration sur les 5 dernières secondes ;
// - panneau qui monte depuis le bas, prix qui défile, badges distance /
//   temps d'approche / type ;
// - bouton Accepter avec halo qui pulse, Ignorer discret ;
// - la sonnerie s'arrête dès le premier appui ;
// - toutes les animations décoratives se coupent si le téléphone est en
//   « animations réduites ».

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/demande_entrante_navigator.dart';
import '../services/prix_ajustable.dart';
import '../services/sonnerie_service.dart';
import '../theme/couleurs_taama.dart';
import '../utils/format.dart';
import '../widgets/couche_carte_taama.dart';
import '../widgets/selecteur_prix.dart';
import '../carte/fond_carte.dart';
import 'navigation_screen.dart';

/// Vitesse moyenne d'approche en ville (Bamako) — même hypothèse que le
/// backend (VITESSE_APPROCHE_KMH dans trajets/views.py) pour rester cohérent
/// avec l'ETA affichée côté client sur l'écran de sélection de véhicule.
const double _vitesseApprocheKmh = 20;

/// Hauteur approximative du panneau bas : la carte se cadre au-dessus.
const double _hauteurPanneau = 360;

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

class _EcranDemandeEntranteState extends State<EcranDemandeEntrante>
    with TickerProviderStateMixin {
  static const int _dureeCompteARebours = 30;

  Map<String, dynamic>? _demande;
  bool _chargement = true;
  bool _demandeIntrouvable = false;
  // Anti double-tap : dès le premier appui (Accepter OU Ignorer), les DEUX
  // boutons sont désactivés — jamais deux POST accepter/refuser en parallèle.
  bool _enTraitement = false;
  // Quel bouton a été pressé (pour n'afficher le chargement que sur lui).
  bool _acceptationEnCours = false;
  int _secondesRestantes = _dureeCompteARebours;
  Timer? _timerCompteARebours;

  // ─── Prix ajustable (limites envoyées par le serveur) ───
  // Null : ni − ni +, seulement « Accepter » au prix standard.
  PrixAjustable? _prixAjustable;
  // Prix de la course choisi, AVANT promo (ce que reçoit le serveur).
  int? _prixChoisi;
  // Prix proposé, en attente de la réponse du client.
  bool _enAttenteClient = false;
  int _secondesClient = 0;
  Timer? _timerAttente;
  bool _verificationEnCours = false;
  // Fin d'attente sans course (refus ou délai) : message et bouton Fermer.
  String? _issueAttente;
  // Le client voit 30 s, le serveur expire à 40 s : au-delà de cette marge,
  // l'écran conclut seul, même sans réponse du réseau.
  static const int _attenteMaxSecondes = 50;

  LatLng? _positionActuelle;
  int? _etaMinutes;
  double? _distanceKm;

  // ─── Affichage ───
  final MapController _carte = MapController();
  bool _cartePrete = false;
  // Anneau fluide (le Timer ci-dessus reste la source de vérité des secondes).
  late final AnimationController _anneau = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _dureeCompteARebours),
  );
  // Entrée du panneau.
  late final AnimationController _entree = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  // Pulsations (halo du bouton, onde du marqueur, pastille du titre).
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _demande = widget.demandeInitiale;
    _verifierEtDemarrer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _timerCompteARebours?.cancel();
    _timerAttente?.cancel();
    _anneau.dispose();
    _entree.dispose();
    _pulse.dispose();
    _carte.dispose();
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
        // Plus rien à accepter : on coupe la sonnerie tout de suite.
        SonnerieService.instance.arreter();
        setState(() {
          _demandeIntrouvable = true;
          _chargement = false;
        });
        return;
      }

      setState(() {
        _demande = actuelle.first;
        _initialiserPrix(actuelle.first);
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
        setState(() {
          _initialiserPrix(_demande!);
          _chargement = false;
        });
        _demarrerCompteARebours();
        _calculerPositionEtEta();
      } else {
        SonnerieService.instance.arreter();
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
    _anneau.forward(from: 0);
    _entree.forward(from: 0);
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
      if (_secondesRestantes <= 5) HapticFeedback.mediumImpact();
    });
  }

  void _arreterCompteARebours() {
    _timerCompteARebours?.cancel();
    _anneau.stop();
  }

  void _initialiserPrix(Map<String, dynamic> demande) {
    _prixAjustable = PrixAjustable.depuisJson(demande['prix_ajustable']);
    _prixChoisi = _prixAjustable?.standard;
  }

  int? get _prixEstime => num.tryParse(_demande?['prix_estime']?.toString() ?? '')?.toInt();

  /// Réduction promo du client (prix standard moins ce qu'il paie) : le
  /// chauffeur voit toujours le montant qu'il encaissera.
  int get _reduction {
    final limites = _prixAjustable;
    final estime = _prixEstime;
    if (limites == null || estime == null) return 0;
    return math.max(0, limites.standard - estime);
  }

  int? get _prixAffiche {
    final choisi = _prixChoisi;
    if (_prixAjustable == null || choisi == null) return _prixEstime;
    return math.max(0, choisi - _reduction);
  }

  bool get _prixModifie => _prixAjustable != null && _prixChoisi != _prixAjustable!.standard;

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
        _distanceKm = distanceKm;
        _etaMinutes = math.max(1, (distanceKm / _vitesseApprocheKmh * 60).round());
      });
      _cadrerCarte();
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

  /// Cadre la carte sur le client et le chauffeur, au-dessus du panneau.
  void _cadrerCarte() {
    if (!_cartePrete || _departLat == null || _departLng == null) return;
    final depart = LatLng(_departLat!, _departLng!);
    final haut = MediaQuery.paddingOf(context).top + 150;
    if (_positionActuelle == null) {
      _carte.move(depart, 15);
      return;
    }
    _carte.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints([depart, _positionActuelle!]),
      padding: EdgeInsets.fromLTRB(60, haut, 60, _hauteurPanneau + 40),
      maxZoom: 16,
    ));
  }

  /// Timer UX arrivé à 0 : ferme l'écran et tente un refus en best-effort.
  /// Ne s'exécute que si l'app est au premier plan (ce timer ne tourne que
  /// tant que ce widget est monté) — pas de garantie hors premier plan, le
  /// timeout autoritatif est côté serveur (Lot 3).
  /// Fermeture décidée par le code (refus réussi, expiration, demande déjà
  /// prise) : pop() et non maybePop(). maybePop() respecte le PopScope, qui
  /// interdit le retour pendant _enTraitement ; il refusait donc en silence
  /// et l'écran restait bloqué, boutons grisés. Le PopScope continue de
  /// bloquer le bouton retour du téléphone pendant un traitement.
  void _fermer() {
    if (!mounted) return;
    final navigateur = Navigator.of(context);
    if (navigateur.canPop()) navigateur.pop();
  }

  Future<void> _expirer() async {
    if (_enTraitement || !mounted) return;
    SonnerieService.instance.arreter();
    setState(() => _enTraitement = true);
    try {
      await ApiService.refuserDemande(widget.demandeId);
      DemandeEntranteNavigator.marquerRefusee(widget.demandeId);
    } catch (e) {
      debugPrint('[DemandeEntrante] Erreur refus après expiration : $e');
    }
    _fermer();
  }

  Future<void> _accepter() async {
    if (_enTraitement) return;
    SonnerieService.instance.arreter();
    HapticFeedback.heavyImpact();
    setState(() {
      _enTraitement = true;
      _acceptationEnCours = true;
    });
    _arreterCompteARebours();

    try {
      // La réponse contient la demande à jour (statut 'en_route') : le
      // backend ne renvoie client_telephone qu'à partir de ce statut, jamais
      // avant — ma copie locale _demande (récupérée avant l'acceptation) l'a
      // forcément à null, donc je ne dois pas m'y fier ici.
      final demandeAcceptee = await ApiService.accepterDemande(widget.demandeId);
      if (!mounted) return;
      _ouvrirNavigation(demandeAcceptee);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demande déjà prise.')),
        );
        _fermer();
      } else if (e.statusCode == 404) {
        _fermer();
      } else {
        setState(() {
          _enTraitement = false;
          _acceptationEnCours = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enTraitement = false;
        _acceptationEnCours = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageErreurLisible(e))),
      );
    }
  }

  /// Course acceptée (au prix standard, ou au prix proposé une fois le client
  /// d'accord) : navigation vers le client. La demande passée est celle du
  /// serveur après acceptation : elle seule porte client_telephone.
  void _ouvrirNavigation(Map<String, dynamic> demandeAcceptee) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EcranNavigation(
          demandeId: widget.demandeId,
          destination: demandeAcceptee['destination']?.toString() ?? '',
          positionClient: (_departLat != null && _departLng != null)
              ? LatLng(_departLat!, _departLng!)
              : null,
          destinationLat: (demandeAcceptee['destination_lat'] as num?)?.toDouble(),
          destinationLng: (demandeAcceptee['destination_lng'] as num?)?.toDouble(),
          telephoneClient: demandeAcceptee['client_telephone']?.toString(),
          arrets: extraireArrets(demandeAcceptee['arrets']),
        ),
      ),
    );
  }

  /// Envoie le prix choisi (≠ standard) : la course reste réservée à ce
  /// chauffeur jusqu'à la réponse du client, attendue ensuite à l'écran.
  Future<void> _proposer() async {
    final prix = _prixChoisi;
    if (_enTraitement || prix == null) return;
    SonnerieService.instance.arreter();
    HapticFeedback.heavyImpact();
    setState(() {
      _enTraitement = true;
      _acceptationEnCours = true;
    });
    _arreterCompteARebours();

    try {
      final reponse = await ApiService.proposerPrix(widget.demandeId, prix);
      if (!mounted) return;
      final restantes = ((reponse['contre_offre'] as Map?)?['secondes_restantes'] as num?)?.toInt();
      setState(() {
        _enAttenteClient = true;
        _acceptationEnCours = false;
        _secondesClient = restantes ?? 30;
      });
      _demarrerAttente();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        _fermer();
        return;
      }
      // Prix refusé par le serveur (limites changées, déjà deux propositions…) :
      // retour au prix standard, la course reste acceptable normalement.
      setState(() {
        _enTraitement = false;
        _acceptationEnCours = false;
        _prixAjustable = null;
        _prixChoisi = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enTraitement = false;
        _acceptationEnCours = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_messageErreurLisible(e))));
    }
  }

  /// Compte à rebours du client et vérification toutes les 3 s : course
  /// acceptée → navigation ; course partie (refus, délai) → message.
  void _demarrerAttente() {
    _timerAttente?.cancel();
    var secondes = 0;
    _timerAttente = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      secondes++;
      if (_secondesClient > 0) setState(() => _secondesClient--);
      if (secondes % 3 == 0) _verifierReponseClient();
      if (secondes >= _attenteMaxSecondes) {
        _finAttente('Pas de réponse du client : la course passe à un autre chauffeur.');
      }
    });
  }

  Future<void> _verifierReponseClient() async {
    if (_verificationEnCours || !_enAttenteClient) return;
    _verificationEnCours = true;
    try {
      final demandes = await ApiService.mesDemandesAssignees();
      if (!mounted || !_enAttenteClient) return;
      final actuelle = demandes
          .cast<Map<String, dynamic>>()
          .where((d) => d['id'] == widget.demandeId)
          .firstOrNull;
      if (actuelle == null) {
        _finAttente('Le client garde le prix standard : la course passe à un autre chauffeur.');
      } else if (actuelle['statut'] == 'en_route') {
        _timerAttente?.cancel();
        _ouvrirNavigation(actuelle);
      }
    } catch (e) {
      // Réseau instable : nouvelle vérification au prochain tour.
      debugPrint('[DemandeEntrante] Vérification de la réponse du client : ${e.runtimeType}');
    } finally {
      _verificationEnCours = false;
    }
  }

  void _finAttente(String message) {
    _timerAttente?.cancel();
    if (!mounted) return;
    DemandeEntranteNavigator.marquerRefusee(widget.demandeId);
    setState(() {
      _enAttenteClient = false;
      _enTraitement = false;
      _issueAttente = message;
    });
  }

  /// Message affiché au conducteur pour une erreur réseau/connexion —
  /// jamais le texte technique brut (ClientException/SocketException/
  /// errno=...), illisible pour un utilisateur qui n'a fait qu'accepter
  /// une course avec une connexion instable.
  String _messageErreurLisible(Object e) {
    final texte = e.toString();
    if (texte.contains('SocketException') ||
        texte.contains('HandshakeException') ||
        texte.contains('TimeoutException') ||
        texte.contains('Failed host lookup')) {
      return 'Pas de connexion internet — vérifiez votre réseau et réessayez.';
    }
    return texte.replaceAll('Exception: ', '');
  }

  Future<void> _ignorer() async {
    if (_enTraitement) return;
    SonnerieService.instance.arreter();
    setState(() => _enTraitement = true);
    _arreterCompteARebours();

    try {
      await ApiService.refuserDemande(widget.demandeId);
    } on ApiException catch (e) {
      // 404 (plus attribuée à toi) ou 400 (déjà acceptée, annulée, expirée) :
      // il n'y a plus rien à refuser, on ferme.
      if (e.statusCode != 404 && e.statusCode != 400) {
        _echecRefus(e.message);
        return;
      }
    } catch (e) {
      _echecRefus(_messageErreurLisible(e));
      return;
    }
    DemandeEntranteNavigator.marquerRefusee(widget.demandeId);
    _fermer();
  }

  /// Le refus n'est PAS enregistré côté serveur : la demande t'est toujours
  /// attribuée. On reste sur l'écran, boutons réactivés, pour réessayer
  /// (compte à rebours arrêté : l'écran ne se ferme pas tout seul).
  void _echecRefus(String message) {
    if (!mounted) return;
    setState(() => _enTraitement = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Le refus n'a pas pu être envoyé : $message"),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(label: 'Réessayer', onPressed: _ignorer),
    ));
  }

  // ─── Construction ───

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Pas de retour arrière accidentel pendant le traitement d'un tap, ni
      // pendant l'attente de la réponse du client (au plus 50 s).
      canPop: !_enTraitement && !_enAttenteClient,
      child: Scaffold(
        backgroundColor: CouleursTaama.indigo,
        body: _chargement
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _demandeIntrouvable
                ? SafeArea(child: _buildDemandeIntrouvable())
                : _buildContenu(),
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
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.update_disabled_rounded, color: Colors.white70, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              'Cette demande n\'est plus disponible.',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Elle a été annulée ou confiée à un autre chauffeur.',
              style: TextStyle(color: Colors.white60),
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
    final aDepart = _departLat != null && _departLng != null;
    final hautSecurite = MediaQuery.paddingOf(context).top;
    final margeAttribution = EdgeInsets.fromLTRB(8, hautSecurite + 8, 8, 8);

    return Stack(
      children: [
        // ─── Carte sombre plein écran ───
        if (aDepart)
          Positioned.fill(
            child: FlutterMap(
              mapController: _carte,
              options: MapOptions(
                initialCenter: LatLng(_departLat!, _departLng!),
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none, // carte décorative : aucun geste
                ),
                onMapReady: () {
                  _cartePrete = true;
                  _cadrerCarte();
                },
              ),
              children: [
                const FondCarteTaama(nuit: true),
                CoucheCarteTaama(
                  nuit: true,
                  reserves: [
                    ZoneReservee.attribution(
                      alignement: Alignment.topLeft,
                      marge: margeAttribution,
                    ),
                  ],
                ),
                if (_positionActuelle != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [_positionActuelle!, LatLng(_departLat!, _departLng!)],
                        color: Colors.white.withValues(alpha: 0.7),
                        strokeWidth: 3,
                        pattern: StrokePattern.dashed(segments: const [8, 8]),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_positionActuelle != null)
                      Marker(
                        point: _positionActuelle!,
                        width: 44,
                        height: 44,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: CouleursTaama.indigo, width: 3),
                          ),
                          child: const Icon(Icons.directions_car_rounded,
                              color: CouleursTaama.indigo, size: 22),
                        ),
                      ),
                    Marker(
                      point: LatLng(_departLat!, _departLng!),
                      width: 90,
                      height: 90,
                      child: _OndeClient(animation: _pulse),
                    ),
                  ],
                ),
                AttributionCarteTaama(
                  nuit: true,
                  alignement: Alignment.topLeft,
                  marge: margeAttribution,
                ),
              ],
            ),
          ),

        // Dégradé : lisibilité du titre en haut et transition vers le panneau.
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  CouleursTaama.indigo.withValues(alpha: aDepart ? 0.55 : 1),
                  CouleursTaama.indigo.withValues(alpha: aDepart ? 0.05 : 1),
                  CouleursTaama.indigo.withValues(alpha: aDepart ? 0.85 : 1),
                ],
                stops: const [0, 0.4, 0.75],
              ),
            ),
          ),
        ),

        // ─── En-tête : titre + anneau ───
        Positioned(
          top: hautSecurite + 32,
          left: 20,
          right: 20,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PastilleEnDirect(animation: _pulse),
                    const SizedBox(height: 10),
                    const Text(
                      'Nouvelle course',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              _AnneauCompteARebours(
                animation: _anneau,
                secondes: _secondesRestantes,
              ),
            ],
          ),
        ),

        // ─── Panneau bas ───
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
              CurvedAnimation(parent: _entree, curve: Curves.easeOutCubic),
            ),
            child: FadeTransition(
              opacity: _entree,
              child: _panneau(demande),
            ),
          ),
        ),
      ],
    );
  }

  Widget _panneau(Map<String, dynamic> demande) {
    final destination = demande['destination']?.toString() ?? '';
    final typeTransport = demande['type_transport']?.toString() ?? '';
    final prix = _prixAffiche;
    final reduit = MediaQuery.disableAnimationsOf(context);
    final ajustable = _prixAjustable != null && _prixChoisi != null && !_enAttenteClient && _issueAttente == null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Prix ajustable (le serveur en a envoyé les limites) : le prix
              // au centre, − et + de chaque côté. Sinon, le prix seul.
              if (ajustable && prix != null) ...[
                const Row(
                  children: [
                    Text(
                      'Prix de la course',
                      style: TextStyle(color: CouleursTaama.grisTexte, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    Spacer(),
                    _PastilleEspeces(),
                  ],
                ),
                const SizedBox(height: 8),
                SelecteurPrix(
                  prix: prix,
                  ecart: _prixChoisi! - _prixAjustable!.standard,
                  pas: _prixAjustable!.pas,
                  surBaisser: _enTraitement || !_prixAjustable!.peutBaisser(_prixChoisi!)
                      ? null
                      : () => setState(() => _prixChoisi = _prixAjustable!.baisser(_prixChoisi!)),
                  surMonter: _enTraitement || !_prixAjustable!.peutMonter(_prixChoisi!)
                      ? null
                      : () => setState(() => _prixChoisi = _prixAjustable!.monter(_prixChoisi!)),
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: prix == null
                          ? const Text('—', style: _stylePrix)
                          : TweenAnimationBuilder<double>(
                              tween: Tween(begin: reduit ? prix.toDouble() : 0, end: prix.toDouble()),
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOutCubic,
                              builder: (context, v, _) => FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(formaterFcfa(v.round()), style: _stylePrix),
                              ),
                            ),
                    ),
                    const _PastilleEspeces(),
                  ],
                ),
              const SizedBox(height: 14),

              // Badges
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_distanceKm != null)
                    _Badge(
                      icone: Icons.near_me_rounded,
                      texte: '${_distanceKm!.toStringAsFixed(1)} km de toi',
                    ),
                  if (_etaMinutes != null)
                    _Badge(icone: Icons.schedule_rounded, texte: '~$_etaMinutes min'),
                  if (typeTransport.isNotEmpty)
                    _Badge(icone: Icons.directions_car_filled_rounded, texte: typeTransport),
                  // Pièce d'identité vérifiée par Taama : un booléen du serveur,
                  // jamais la pièce. Absent ou faux : rien n'est affiché.
                  if (_demande?['client_verifie'] == true)
                    const _Badge(icone: Icons.verified_user_rounded, texte: 'Client vérifié'),
                ],
              ),
              const SizedBox(height: 16),

              // Destination
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: CouleursTaama.indigo.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: CouleursTaama.terreCuite.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.flag_rounded, color: CouleursTaama.terreCuite),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Destination',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            destination.isEmpty ? '—' : destination,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: CouleursTaama.indigo,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (_issueAttente != null)
                _buildIssueAttente()
              else if (_enAttenteClient)
                _buildAttenteClient()
              else
                _buildBoutons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttenteClient() {
    final reduit = MediaQuery.disableAnimationsOf(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CouleursTaama.indigo.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: reduit
                    ? const Icon(Icons.hourglass_top_rounded, size: 20, color: CouleursTaama.terreCuite)
                    : const CircularProgressIndicator(strokeWidth: 2.5, color: CouleursTaama.terreCuite),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'En attente de la réponse du client',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: CouleursTaama.indigo),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _secondesClient > 0
                ? 'Il a encore $_secondesClient s pour accepter ${formaterFcfa(_prixAffiche ?? 0)}.'
                : 'Réponse attendue d’un instant à l’autre…',
            style: const TextStyle(fontSize: 14, color: CouleursTaama.grisTexte),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (_secondesClient / 30).clamp(0.0, 1.0),
              minHeight: 6,
              color: CouleursTaama.terreCuite,
              backgroundColor: CouleursTaama.terreCuite.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueAttente() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _issueAttente!,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: CouleursTaama.indigo),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _fermer,
            style: ElevatedButton.styleFrom(
              backgroundColor: CouleursTaama.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('Fermer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  static const TextStyle _stylePrix = TextStyle(
    color: CouleursTaama.terreCuite,
    fontWeight: FontWeight.w900,
    fontSize: 34,
    height: 1,
  );

  Widget _buildBoutons() {
    return Row(
      children: [
        SizedBox(
          height: 60,
          child: OutlinedButton(
            onPressed: _enTraitement ? null : _ignorer,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(96, 60),
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: (_enTraitement && !_acceptationEnCours)
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade600),
                  )
                : const Text('Ignorer', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final t = _enTraitement ? 0.0 : _pulse.value;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.45 * (1 - t)),
                      blurRadius: 6 + 18 * t,
                      spreadRadius: 6 * t,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: SizedBox(
              height: 60,
              child: ElevatedButton(
                // Prix changé : le client doit d'abord accepter ce prix.
                onPressed: _enTraitement ? null : (_prixModifie ? _proposer : _accepter),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  disabledBackgroundColor: Colors.green.shade300,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: _acceptationEnCours
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_prixModifie ? Icons.send_rounded : Icons.check_circle_rounded, size: 24),
                          const SizedBox(width: 8),
                          Text(_prixModifie ? 'Proposer ce prix' : 'Accepter',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Widgets ───

/// Mode de paiement de la course.
class _PastilleEspeces extends StatelessWidget {
  const _PastilleEspeces();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.payments_rounded, size: 16, color: Colors.green.shade700),
          const SizedBox(width: 4),
          Text(
            'Espèces',
            style: TextStyle(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grand anneau du compte à rebours : fluide, blanc → or → rouge.
class _AnneauCompteARebours extends StatelessWidget {
  const _AnneauCompteARebours({required this.animation, required this.secondes});

  final Animation<double> animation;
  final int secondes;

  @override
  Widget build(BuildContext context) {
    final reduit = MediaQuery.disableAnimationsOf(context);
    final couleur = secondes <= 5
        ? Colors.redAccent
        : (secondes <= 10 ? CouleursTaama.or : Colors.white);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final restant = reduit ? secondes / 30 : (1 - animation.value).clamp(0.0, 1.0);
        final echelle = (!reduit && secondes <= 5) ? 1 + 0.06 * math.sin(animation.value * 30 * 2 * math.pi) : 1.0;
        return Transform.scale(
          scale: echelle,
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.25),
                  ),
                ),
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: restant,
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    color: couleur,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$secondes',
                      style: TextStyle(
                        color: couleur,
                        fontWeight: FontWeight.w900,
                        fontSize: 28,
                        height: 1,
                      ),
                    ),
                    const Text(
                      'sec',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pastille « EN DIRECT » avec point qui clignote.
class _PastilleEnDirect extends StatelessWidget {
  const _PastilleEnDirect({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: CouleursTaama.terreCuite,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: animation,
            builder: (context, _) => Opacity(
              opacity: 0.4 + 0.6 * (1 - animation.value),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'DEMANDE EN DIRECT',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Point de prise en charge : deux ondes qui s'élargissent.
class _OndeClient extends StatelessWidget {
  const _OndeClient({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        Widget onde(double decalage) {
          final t = (animation.value + decalage) % 1;
          return Opacity(
            opacity: (1 - t) * 0.7,
            child: Container(
              width: 30 + 60 * t,
              height: 30 + 60 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: CouleursTaama.terreCuite, width: 2),
                color: CouleursTaama.terreCuite.withValues(alpha: 0.15),
              ),
            ),
          );
        }

        return Stack(
          alignment: Alignment.center,
          children: [onde(0), onde(0.5), child!],
        );
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: CouleursTaama.terreCuite,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
        ),
        child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icone, required this.texte});
  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: CouleursTaama.indigo.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 16, color: CouleursTaama.indigo),
          const SizedBox(width: 5),
          Text(
            texte,
            style: const TextStyle(
              color: CouleursTaama.indigo,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}