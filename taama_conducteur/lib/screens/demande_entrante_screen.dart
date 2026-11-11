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
import '../widgets/decision_demande.dart';
import '../widgets/selecteur_prix.dart';
import '../carte/fond_carte.dart';
import 'navigation_screen.dart';

/// Vitesse moyenne d'approche en ville (Bamako) — même hypothèse que le
/// backend (VITESSE_APPROCHE_KMH dans trajets/views.py) pour rester cohérent
/// avec l'ETA affichée côté client sur l'écran de sélection de véhicule.
const double _vitesseApprocheKmh = 20;

/// Hauteur habituelle du panneau bas, tant qu'il n'est pas mesuré : la
/// carte se cadre au-dessus.
const double _hauteurPanneau = 440;

// Le panneau monte au plus jusque sous le compte à rebours (en-tête à 32 dp
// sous la zone sûre, anneau de 84 dp, 12 dp d'air) ; au-delà, les
// informations défilent. Jamais moins que ce qui doit tenir : marges (22 et
// 16), espace (18), boutons (124) et au moins 40 dp d'informations.
const double _basEnTete = 32 + 84 + 12;
const double _hauteurFixePanneau = 22 + 16 + 18 + 124 + 40;

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
  // « Contre-proposer » touché : le − et le + remplacent le prix.
  bool _modeContre = false;
  // Temps affiché au client pour répondre à une contre-proposition (le
  // serveur expire 10 s plus tard : contre_offre.DELAI_EXPIRATION_SECONDES).
  static const int _dureeReponseClient = 45;
  int _secondesClient = 0;
  Timer? _timerAttente;
  bool _verificationEnCours = false;
  // Fin d'attente sans course (refus ou délai) : message et bouton Fermer.
  String? _issueAttente;
  // Le client voit 45 s, le serveur expire à 55 s : au-delà de cette marge,
  // l'écran conclut seul, même sans réponse du réseau.
  static const int _attenteMaxSecondes = 65;

  LatLng? _positionActuelle;
  int? _etaMinutes;
  double? _distanceKm;

  // ─── Affichage ───
  final MapController _carte = MapController();
  bool _cartePrete = false;
  // Panneau du bas, mesuré pour cadrer la carte au-dessus.
  final GlobalKey _clePanneau = GlobalKey();
  // Informations du panneau (défilent sur les petits téléphones).
  final ScrollController _defilementInfos = ScrollController();
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
    _defilementInfos.dispose();
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
    // Apps récentes : `contre_proposition` (référence = offre du client) ;
    // `prix_ajustable` reste pour les serveurs d'avant la négociation.
    _prixAjustable = PrixAjustable.depuisJson(demande['contre_proposition'] ?? demande['prix_ajustable']);
    _prixChoisi = _prixAjustable?.reference;
  }

  int? get _prixOffert => num.tryParse(_demande?['prix_offert']?.toString() ?? '')?.toInt();
  int? get _prixStandard => num.tryParse(_demande?['prix_standard']?.toString() ?? '')?.toInt();

  /// Le client a offert un autre prix que le standard.
  bool get _offreClient => _prixOffert != null && _prixStandard != null && _prixOffert != _prixStandard;

  int? get _prixEstime => num.tryParse(_demande?['prix_estime']?.toString() ?? '')?.toInt();

  /// Réduction promo du client (prix de référence moins ce qu'il paie) : le
  /// chauffeur voit toujours le montant qu'il encaissera.
  int get _reduction {
    // Référence : celle des limites, sinon l'offre du client, sinon le
    // standard (serveur sans limites, ou prix refusé par le serveur).
    final reference = _prixAjustable?.reference ?? (_offreClient ? _prixOffert : _prixStandard);
    final estime = _prixEstime;
    if (reference == null || estime == null) return 0;
    return math.max(0, reference - estime);
  }

  int? get _prixAffiche {
    final choisi = _prixChoisi;
    if (_prixAjustable == null || choisi == null) return _prixEstime;
    return math.max(0, choisi - _reduction);
  }

  bool get _prixModifie => _prixAjustable != null && _prixChoisi != _prixAjustable!.reference;

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
      // Après la mise en page : les badges distance et temps ont pu agrandir
      // le panneau.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _cadrerCarte();
      });
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

  double _hauteurMaxPanneau() {
    final zoneSure = MediaQuery.paddingOf(context);
    return math.max(
      _hauteurFixePanneau + zoneSure.bottom,
      MediaQuery.sizeOf(context).height - zoneSure.top - _basEnTete,
    );
  }

  /// Cadre la carte sur le client et le chauffeur, au-dessus du panneau.
  void _cadrerCarte() {
    if (!_cartePrete || _departLat == null || _departLng == null) return;
    final depart = LatLng(_departLat!, _departLng!);
    final zoneSure = MediaQuery.paddingOf(context);
    final haut = zoneSure.top + 150;
    // Au-dessus du panneau tel qu'il est affiché (mesuré), sinon de sa
    // hauteur habituelle.
    final hauteurEcran = MediaQuery.sizeOf(context).height;
    final boite = _clePanneau.currentContext?.findRenderObject();
    final panneau = boite is RenderBox && boite.hasSize
        ? boite.size.height
        : math.min(_hauteurPanneau, _hauteurMaxPanneau());
    final bas = panneau + 40;
    // Pas de position du chauffeur, ou trop peu de place pour cadrer les deux
    // (petit téléphone) : le départ au milieu de la bande de carte visible,
    // entre le compte à rebours et le panneau — pas au centre de l'écran.
    if (_positionActuelle == null || hauteurEcran - haut - bas < 80) {
      final hautBande = zoneSure.top + _basEnTete;
      final basBande = hauteurEcran - panneau;
      // Bande vide (paysage) : ce qui reste visible au-dessus du panneau,
      // derrière l'en-tête — jamais sous le panneau.
      final y = basBande > hautBande ? (hautBande + basBande) / 2 : (zoneSure.top + basBande) / 2;
      _carte.move(depart, 15, offset: Offset(0, y - hauteurEcran / 2));
      return;
    }
    _carte.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints([depart, _positionActuelle!]),
      padding: EdgeInsets.fromLTRB(60, haut, 60, bas),
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
      // L'écran suit l'état renvoyé par le serveur (la demande), jamais un
      // état supposé. Corps sans état reconnu : on relit la demande.
      if (_suivreEtat(reponse) || await _suivreLeServeur()) return;
      if (!mounted) return;
      setState(() {
        _enTraitement = false;
        _acceptationEnCours = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La proposition n’a pas pu être confirmée : réessaie.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        _fermer();
        return;
      }
      // Refus du serveur : la proposition a pu partir lors d'un essai dont la
      // réponse s'est perdue. Le serveur fait foi.
      if (await _suivreLeServeur()) return;
      if (!mounted) return;
      // Prix refusé par le serveur (limites changées, déjà deux propositions…) :
      // retour au prix standard, la course reste acceptable normalement.
      setState(() {
        _enTraitement = false;
        _acceptationEnCours = false;
        _modeContre = false;
        _prixAjustable = null;
        _prixChoisi = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      // Réponse perdue (réseau, délai) : la proposition est peut-être
      // enregistrée. Le serveur fait foi.
      if (await _suivreLeServeur()) return;
      if (!mounted) return;
      setState(() {
        _enTraitement = false;
        _acceptationEnCours = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_messageErreurLisible(e))));
    }
  }

  /// Après un échec de « Proposer ce prix », relit la demande et suit le
  /// serveur : contre-proposition enregistrée → attente du client ; course
  /// acceptée → navigation ; demande partie → fermeture. Vrai si l'écran a
  /// suivi ; faux si elle attend toujours une réponse (ou si le réseau ne
  /// répond pas) : l'erreur s'affiche, le chauffeur peut réessayer.
  Future<bool> _suivreLeServeur() async {
    final List<dynamic> demandes;
    try {
      demandes = await ApiService.mesDemandesAssignees();
    } catch (_) {
      return false;
    }
    if (!mounted) return true;
    final actuelle = demandes
        .whereType<Map<String, dynamic>>()
        .where((d) => d['id'] == widget.demandeId)
        .firstOrNull;
    if (actuelle == null) {
      _fermer();
      return true;
    }
    return _suivreEtat(actuelle);
  }

  /// Suit l'état d'une demande renvoyé par le serveur : contre-proposition
  /// enregistrée → attente du client (temps et prix du serveur) ; course
  /// acceptée → navigation. Vrai si l'écran a suivi ; faux pour tout autre
  /// état (la demande attend encore une réponse, ou état inconnu).
  bool _suivreEtat(Map<String, dynamic> demande) {
    switch (demande['statut']) {
      case 'contre_offre':
        final offre = demande['contre_offre'];
        final restantes = offre is Map ? (offre['secondes_restantes'] as num?)?.toInt() : null;
        final propose = offre is Map ? (offre['prix_propose'] as num?)?.toInt() : null;
        setState(() {
          _enAttenteClient = true;
          _modeContre = false;
          _acceptationEnCours = false;
          if (propose != null) _prixChoisi = propose;
          _secondesClient = restantes ?? _dureeReponseClient;
        });
        _demarrerAttente();
        return true;
      case 'en_route':
        _ouvrirNavigation(demande);
        return true;
    }
    return false;
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
        _finAttente(_messageClientGarde);
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

  /// Contre-proposition refusée : le client garde son offre s'il en avait
  /// fait une, sinon le prix standard (comme la notification du serveur).
  String get _messageClientGarde => _offreClient
      ? 'Le client garde son offre : la course passe à un autre chauffeur.'
      : 'Le client garde le prix standard : la course passe à un autre chauffeur.';

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
      // pendant l'attente de la réponse du client. En contre-proposition, le
      // retour revient à la vue de départ, comme « Annuler ».
      canPop: !_enTraitement && !_enAttenteClient && !_modeContre,
      onPopInvokedWithResult: (aQuitte, _) {
        if (!aQuitte && _modeContre && !_enTraitement && !_enAttenteClient) _annulerContre();
      },
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
                    // Une seule ligne, réduite si l'écran est étroit : l'en-tête
                    // garde la hauteur de l'anneau, sous laquelle monte le panneau.
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Nouvelle course',
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
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
              key: _clePanneau,
              opacity: _entree,
              // Le panneau change de taille (contre-proposition, attente,
              // issue, badges) : la carte se recadre au-dessus.
              child: NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _cadrerCarte();
                  });
                  return true;
                },
                child: SizeChangedLayoutNotifier(child: _panneau(demande)),
              ),
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
    final ajustable = _prixAjustable != null && _prixChoisi != null && !_enAttenteClient && _issueAttente == null;

    return Container(
      key: const ValueKey('panneau-demande'),
      // Jusque sous le compte à rebours, au plus : le titre et l'anneau
      // restent visibles, en portrait comme en paysage.
      constraints: BoxConstraints(maxHeight: _hauteurMaxPanneau()),
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
              // Seules les informations défilent (petits téléphones) : les
              // boutons restent toujours visibles, en bas du panneau.
              Flexible(
                // Barre visible dès que les informations dépassent : le
                // chauffeur voit qu'il peut faire défiler.
                child: Scrollbar(
                  controller: _defilementInfos,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _defilementInfos,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Le prix encaissé (l'offre du client, sinon le prix de la course).
                        // Après « Contre-proposer » : le − et le + à partir de ce prix.
                        if (_modeContre && ajustable && prix != null) ...[
                          const Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Ta contre-proposition',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: CouleursTaama.grisTexte, fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                              ),
                              SizedBox(width: 8),
                              PastilleEspeces(),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelecteurPrix(
                            prix: prix,
                            ecart: _prixChoisi! - _prixAjustable!.reference,
                            libelleReference: _offreClient ? 'l’offre du client' : 'le prix standard',
                            pas: _prixAjustable!.pas,
                            surBaisser: _enTraitement || !_prixAjustable!.peutBaisser(_prixChoisi!)
                                ? null
                                : () => setState(() => _prixChoisi = _prixAjustable!.baisser(_prixChoisi!)),
                            surMonter: _enTraitement || !_prixAjustable!.peutMonter(_prixChoisi!)
                                ? null
                                : () => setState(() => _prixChoisi = _prixAjustable!.monter(_prixChoisi!)),
                          ),
                        ] else
                          BlocPrixDemande(
                            prix: prix,
                            prixStandard: _prixStandard,
                            prixOffert: _prixOffert,
                            reduction: _reduction,
                            // Après « Proposer ce prix » : le prix affiché est le sien.
                            contreProposition: _enAttenteClient || _issueAttente != null,
                          ),
                        const SizedBox(height: 14),

                        // Destination juste sous le prix : visible sans faire défiler.
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
                      ],
                    ),
                  ),
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
              value: (_secondesClient / _dureeReponseClient).clamp(0.0, 1.0),
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


  Widget _buildBoutons() {
    final ajustable = _prixAjustable != null && _prixChoisi != null;
    return ActionsDemande(
      prix: _prixAffiche,
      contrePossible: ajustable,
      modeContre: _modeContre && ajustable,
      prixModifie: _prixModifie,
      enTraitement: _enTraitement,
      envoiEnCours: _acceptationEnCours,
      pulse: MediaQuery.disableAnimationsOf(context) ? null : _pulse,
      onAccepter: _accepter,
      onRefuser: _ignorer,
      onContreProposer: () {
        // Premier geste du chauffeur : la sonnerie s'arrête, comme pour
        // accepter ou refuser.
        SonnerieService.instance.arreter();
        setState(() {
          _modeContre = true;
          _prixChoisi = _prixAjustable!.reference;
        });
      },
      onProposer: _proposer,
      onAnnulerContre: _annulerContre,
    );
  }

  /// Retour à la vue de départ (« Annuler » ou geste retour) : rien n'a été
  /// envoyé, le prix redevient celui de la demande.
  void _annulerContre() {
    setState(() {
      _modeContre = false;
      _prixChoisi = _prixAjustable?.reference;
    });
  }
}

// ─── Widgets ───

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
          // Écran étroit ou grand texte : le libellé rétrécit, jamais coupé.
          const Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'DEMANDE EN DIRECT',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
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