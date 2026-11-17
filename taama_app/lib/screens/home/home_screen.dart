// lib/screens/home/home_screen.dart
//
// HomeScreen v4 — écran d'accueil client, PUREMENT présentationnel :
// aucune requête ici, tout arrive par le constructeur (voir home_page.dart).
//
// Nouveautés v4 (maquette « Taama accueil client », écran 1) :
// - carte plus grande, chauffeurs qui glissent, position qui pulse ;
// - carte verrouillée plein nord (plus de texte à l'envers) ;
// - MapController interne : le recentrage fonctionne vraiment ;
// - feuille du bas qui monte + apparition en cascade des blocs ;
// - exemples de destination qui défilent (tirés des favoris réels) ;
// - mode gratuit : aucun solde/portefeuille, bandeau « espèces ».
// Toutes les animations respectent « réduire les animations ».

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/taama_theme.dart';
import '../../utils/format.dart';
import '../../widgets/couche_carte_taama.dart';
import '../../widgets/invitation_identite.dart';
import '../../widgets/photo_avatar.dart';
import '../../widgets/taama/anime_en_boucle.dart';
import '../../widgets/taama/couche_chauffeurs_accueil.dart';
import '../../widgets/taama/fiche_chauffeurs_proches.dart';
import '../../widgets/taama/point_position.dart';
import '../../widgets/taama/tuile_service.dart';
import 'home_models.dart';

export 'home_models.dart';
export '../../widgets/invitation_identite.dart' show InvitationIdentite;

const LatLng _centreBamako = LatLng(12.6392, -8.0029);
// Assez près pour voir les rues et les bâtiments autour du client.
const double _zoomInitial = 16;

/// Part de l'écran donnée à la carte (le reste : la feuille du bas).
const double _partCarte = 0.58;

/// Attribution OSM/MapTiler : bas gauche de la carte, juste au-dessus de la
/// feuille, jamais recouverte (obligation de licence) : le bandeau et les
/// boutons se posent au-dessus d'elle ([_dessusAttribution]). La même valeur
/// est passée à CoucheCarteTaama pour qu'aucune étiquette ne s'y pose.
const EdgeInsets _margeAttribution = EdgeInsets.all(6);

/// Bas du bandeau et des boutons, depuis le bas de la carte : la marge de
/// l'attribution, sa hauteur à 130 % de texte (≈ 19), un écart.
const double _dessusAttribution = 34;

/// Barre du haut (avatar, départ) : 12 de marge + 48, sous la barre d'état.
const double _hauteurBarreHaute = 68;

/// Boutons de la carte (zoom, recentrage) et bandeau : hauteur réservée en
/// bas à droite, où aucune étiquette de lieu ne se pose.
const double _largeurBoutons = 48;
const double _hauteurBoutons = 44 * 2 + 1 + 10 + 48;
const double _hauteurBandeau = 64; // deux lignes à 130 % de texte

const double _zoomMin = 12;
const double _zoomMax = 19;

/// Texte du bandeau des chauffeurs proches. [minutes] : le plus court des
/// temps d'approche reçus, calculé par le serveur depuis la position arrondie
/// (d'où « environ ») ; null : pas de temps affiché, jamais inventé.
String texteProximite({required bool chargement, required int nombre, int? minutes}) {
  if (chargement) return 'Recherche de chauffeurs…';
  if (nombre == 0) {
    // On peut commander sans chauffeur en ligne : la recherche dure 15 min.
    return 'Aucun chauffeur en ligne près de toi pour l’instant. '
        'Tu peux commander : on cherche pour toi.';
  }
  final proches = nombre == 1 ? '1 chauffeur proche' : '$nombre chauffeurs proches';
  // Espace insécable : jamais « environ 2 » en fin de ligne et « min » seul.
  return minutes == null ? proches : '$proches, environ $minutes\u00a0min';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.paiementActif,
    required this.coucheFond,
    this.nuit = false,
    this.prenom,
    this.quartier,
    this.urlPhotoProfil,
    this.soldeFcfa = 0,
    this.services = const [],
    this.suggestions = const [],
    this.conducteursProches = const [],
    this.positionClient,
    this.precisionPositionM,
    this.capPosition,
    this.positionApproximative = false,
    this.chargementConducteurs = false,
    this.derniereCourse,
    this.courseActive,
    this.onReprendreCourse,
    this.invitationIdentite,
    this.onVerifierIdentite,
    this.onMasquerInvitationIdentite,
    required this.onChercherDestination,
    required this.onSuggestion,
    required this.onAjouterAdresse,
    required this.onService,
    required this.onReserver,
    required this.onColis,
    this.onPortefeuille,
    this.onProfil,
    this.onRecentrerCarte,
    this.onRefaireCourse,
    this.onDicterDestination,
    this.onActualiser,
  });

  final bool paiementActif;

  /// Couche de tuiles seule, ex. `FondCarteTaama(...)`. Les quartiers
  /// (CoucheCarteTaama) et l'attribution sont ajoutés ici, dans le bon ordre.
  final Widget coucheFond;

  /// Étiquettes et attribution en couleurs de nuit.
  final bool nuit;

  final String? prenom;
  final String? quartier;
  final String? urlPhotoProfil;
  final int soldeFcfa;
  final List<ServiceAccueil> services;
  final List<SuggestionDestination> suggestions;
  final List<ConducteurProche> conducteursProches;
  final LatLng? positionClient;

  /// Précision de [positionClient] en mètres (cercle autour du point) ;
  /// null : inconnue, pas de cercle.
  final double? precisionPositionM;

  /// Direction suivie (degrés depuis le nord), null à l'arrêt.
  final double? capPosition;

  /// Dernière position connue du téléphone, pas encore confirmée par le GPS.
  final bool positionApproximative;

  /// Au-delà, le cercle de précision couvrirait le quartier : pas de cercle.
  static const double precisionMaxAfficheeM = 1000;
  final bool chargementConducteurs;
  final DerniereCourse? derniereCourse;

  /// Course non terminée à reprendre (null s'il n'y en a pas).
  final CourseActive? courseActive;
  final ValueChanged<CourseActive>? onReprendreCourse;

  /// Invitation à faire vérifier son identité (facultative), null : rien.
  final InvitationIdentite? invitationIdentite;
  final VoidCallback? onVerifierIdentite;
  final VoidCallback? onMasquerInvitationIdentite;

  final VoidCallback onChercherDestination;
  final ValueChanged<SuggestionDestination> onSuggestion;
  final VoidCallback onAjouterAdresse;
  final ValueChanged<ServiceAccueil> onService;
  final VoidCallback onReserver;
  final VoidCallback onColis;
  final VoidCallback? onPortefeuille;
  final VoidCallback? onProfil;
  final Future<void> Function()? onRecentrerCarte;
  final ValueChanged<DerniereCourse>? onRefaireCourse;
  final VoidCallback? onDicterDestination;
  final Future<void> Function()? onActualiser;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final MapController _carte = MapController();
  bool _cartePrete = false;

  /// La carte suit la position du client, comme les cartes du téléphone,
  /// jusqu'à ce qu'il la fasse glisser lui-même ; « recentrer » la remet.
  bool _suivre = true;

  late final AnimationController _entree =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entree.status == AnimationStatus.dismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _entree.value = 1;
      } else {
        _entree.forward();
      }
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen ancien) {
    super.didUpdateWidget(ancien);
    final avant = ancien.positionClient;
    final apres = widget.positionClient;
    if (apres == null) return;
    // Première position : toujours. Ensuite, seulement en suivi.
    final aBouge = avant == null ||
        (_suivre && const Distance().as(LengthUnit.Meter, avant, apres) > 2);
    if (aBouge) {
      // Jamais de move() pendant un build : on attend la fin de la frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _deplacerCarte(apres);
      });
    }
  }

  @override
  void dispose() {
    _entree.dispose();
    _carte.dispose();
    super.dispose();
  }

  void _deplacerCarte(LatLng point) {
    if (!_cartePrete) return;
    _carte.move(point, _carte.camera.zoom);
  }

  void _zoomer(double pas) {
    if (!_cartePrete) return;
    final camera = _carte.camera;
    _carte.move(camera.center, (camera.zoom + pas).clamp(_zoomMin, _zoomMax));
  }

  Future<void> _recentrer() async {
    _suivre = true;
    await widget.onRecentrerCarte?.call();
    if (!mounted) return;
    final p = widget.positionClient;
    if (p != null) _deplacerCarte(p);
  }

  ServiceAccueil _service(String code, String libelle) =>
      widget.services.firstWhere(
        (s) => s.code == code,
        orElse: () => ServiceAccueil(code: code, libelle: libelle),
      );

  /// Fondu + montée de 16 px, déclenché à [debut] (0..1) de l'entrée.
  Widget _apparition(double debut, Widget enfant) {
    final intervalle = Interval(debut, math.min(1.0, debut + 0.45), curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: _entree,
      child: enfant,
      builder: (context, child) {
        final t = intervalle.transform(_entree.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 16), child: child),
        );
      },
    );
  }

  // ─── Construction ───

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: TaamaColors.background,
      child: LayoutBuilder(
        builder: (context, contraintes) {
          final hauteurCarte = contraintes.maxHeight * _partCarte;
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                // La carte s'arrête au bord de la feuille : le fond neutre de
                // l'écran remplit les coins arrondis, sans étiquette qui
                // dépasse dessous.
                height: hauteurCarte,
                child: _carteWidget(),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _barreHaute(),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                // Au-dessus de l'attribution (bas gauche), jamais dessus.
                bottom: contraintes.maxHeight - hauteurCarte + _dessusAttribution,
                child: _barreBasCarte(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                top: hauteurCarte,
                child: _feuilleAnimee(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _carteWidget() {
    final position = widget.positionClient;
    return FlutterMap(
      mapController: _carte,
      options: MapOptions(
        initialCenter: position ?? _centreBamako,
        initialZoom: _zoomInitial,
        // Plein nord : la rotation retournait les noms de rue (tuiles raster).
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _cartePrete = true;
          final p = widget.positionClient;
          if (p != null) _deplacerCarte(p);
        },
        // Le client fait glisser la carte : elle ne le suit plus.
        onPositionChanged: (_, parGeste) {
          if (parGeste) _suivre = false;
        },
      ),
      children: [
        widget.coucheFond,
        CoucheCarteTaama(
          nuit: widget.nuit,
          // Aucune étiquette de lieu sous ce qui est posé sur la carte : barre
          // du haut, bandeau, boutons, attribution.
          reserves: [
            const ZoneReservee.attribution(
              alignement: Alignment.bottomLeft,
              marge: _margeAttribution,
            ),
            ZoneReservee(
              alignement: Alignment.topCenter,
              taille: Size(10000, MediaQuery.paddingOf(context).top + _hauteurBarreHaute + 6),
            ),
            const ZoneReservee(
              alignement: Alignment.bottomCenter,
              taille: Size(10000, _dessusAttribution + _hauteurBandeau + 4),
            ),
            const ZoneReservee(
              alignement: Alignment.bottomRight,
              taille: Size(_largeurBoutons + 22,
                  _dessusAttribution + _hauteurBandeau + 10 + _hauteurBoutons + 6),
            ),
          ],
        ),
        if (position != null &&
            !widget.positionApproximative &&
            widget.precisionPositionM != null &&
            widget.precisionPositionM! <= HomeScreen.precisionMaxAfficheeM)
          CircleLayer(
            circles: [
              CircleMarker(
                point: position,
                radius: widget.precisionPositionM!,
                useRadiusInMeter: true,
                color: TaamaColors.position.withValues(alpha: 0.12),
                borderColor: TaamaColors.position.withValues(alpha: 0.35),
                borderStrokeWidth: 1,
              ),
            ],
          ),
        CoucheChauffeursAccueil(
          conducteurs: widget.conducteursProches,
          nuit: widget.nuit,
          // Fiche du ou des chauffeurs touchés : rien n'est commandé ici, le
          // choix vient après la destination et le prix.
          onGroupe: (chauffeurs) =>
              afficherFicheChauffeursProches(context, chauffeurs: chauffeurs),
        ),
        if (position != null)
          MarkerLayer(
            markers: [
              Marker(
                point: position,
                width: 96,
                height: 96,
                // Dessiné par-dessus les pastilles, mais transparent aux
                // appuis : un chauffeur dans la même cellule que le client
                // reste touchable.
                child: IgnorePointer(
                  child: PointPosition(
                    cap: widget.capPosition,
                    approximatif: widget.positionApproximative,
                  ),
                ),
              ),
            ],
          ),
        // TOUJOURS en dernier : rien ne doit la recouvrir.
        AttributionCarteTaama(
          nuit: widget.nuit,
          alignement: Alignment.bottomLeft,
          marge: _margeAttribution,
        ),
      ],
    );
  }

  Widget _barreHaute() {
    return Row(
      children: [
        _Avatar(prenom: widget.prenom, urlPhoto: widget.urlPhotoProfil, onTap: widget.onProfil),
        const SizedBox(width: 10),
        Expanded(
          child: _PiluleDepart(
            libelle: widget.quartier ?? 'Ma position',
            onTap: widget.onChercherDestination,
          ),
        ),
        if (widget.paiementActif) ...[
          const SizedBox(width: 10),
          _PastilleSolde(soldeFcfa: widget.soldeFcfa, onTap: widget.onPortefeuille),
        ],
      ],
    );
  }

  static int? _minutesLaPlusCourte(List<ConducteurProche> conducteurs) {
    int? plusCourt;
    for (final c in conducteurs) {
      final m = c.minutesAvant;
      if (m != null && (plusCourt == null || m < plusCourt)) plusCourt = m;
    }
    return plusCourt;
  }

  /// Boutons de la carte (zoom, recentrage) à droite, puis le bandeau des
  /// chauffeurs proches sur toute la largeur : une ligne le plus souvent.
  Widget _barreBasCarte() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _CommandesZoom(onPlus: () => _zoomer(1), onMoins: () => _zoomer(-1)),
        const SizedBox(height: 10),
        _BoutonRond(
          icone: Icons.near_me_rounded,
          info: 'Recentrer sur ma position',
          onPressed: widget.onRecentrerCarte == null ? null : _recentrer,
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: _PastilleProximite(
            texte: texteProximite(
              chargement: widget.chargementConducteurs,
              nombre: widget.conducteursProches.length,
              minutes: _minutesLaPlusCourte(widget.conducteursProches),
            ),
            actif: widget.conducteursProches.isNotEmpty,
            onTap: widget.onActualiser,
          ),
        ),
      ],
    );
  }

  Widget _feuilleAnimee() {
    final montee = const Interval(0, 0.55, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: _entree,
      child: _feuille(),
      builder: (context, child) => Transform.translate(
        offset: Offset(0, (1 - montee.transform(_entree.value)) * 140),
        child: child,
      ),
    );
  }

  Widget _feuille() {
    final exemples = [for (final s in widget.suggestions) s.libelle];
    final derniere = widget.derniereCourse;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: TaamaShadows.floating,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: TaamaColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (widget.courseActive != null && widget.onReprendreCourse != null) ...[
              _BanniereCourseActive(
                course: widget.courseActive!,
                onTap: () => widget.onReprendreCourse!(widget.courseActive!),
              ),
              const SizedBox(height: 14),
            ],
            _apparition(0.15, _salutation()),
            const SizedBox(height: 14),
            _apparition(
              0.25,
              Row(
                children: [
                  Expanded(
                    child: _BarreRecherche(
                      exemples: exemples,
                      onTap: widget.onChercherDestination,
                      onDicter: widget.onDicterDestination,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BoutonPlusTard(onTap: widget.onReserver),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _apparition(
              0.35,
              _LieuxEnregistres(
                suggestions: widget.suggestions,
                onSuggestion: widget.onSuggestion,
                onAjouter: widget.onAjouterAdresse,
              ),
            ),
            const SizedBox(height: 16),
            _grilleServices(),
            if (derniere != null && widget.onRefaireCourse != null) ...[
              const SizedBox(height: 14),
              _apparition(
                0.8,
                _CarteDerniereCourse(
                  course: derniere,
                  onTap: () => widget.onRefaireCourse!(derniere),
                ),
              ),
            ],
            if (!widget.paiementActif) ...[
              const SizedBox(height: 14),
              _apparition(0.9, const _BandeauEspeces()),
            ],
            if (widget.invitationIdentite != null &&
                widget.onVerifierIdentite != null &&
                widget.onMasquerInvitationIdentite != null) ...[
              const SizedBox(height: 14),
              _apparition(
                0.95,
                BandeauInvitationIdentite(
                  invitation: widget.invitationIdentite!,
                  onOuvrir: widget.onVerifierIdentite!,
                  onMasquer: widget.onMasquerInvitationIdentite!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _salutation() {
    final prenom = widget.prenom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (prenom == null || prenom.isEmpty) ? 'Bonjour' : 'Bonjour $prenom',
          style: TaamaText.muted.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 2),
        Text('Où allons-nous ?', style: TaamaText.title.copyWith(fontSize: 24)),
      ],
    );
  }

  Widget _grilleServices() {
    final moto = _service(CodesTransport.moto, 'Moto');
    final voiture = _service(CodesTransport.voiture, 'Voiture');
    String? desPrix(ServiceAccueil s) =>
        s.prixMinFcfa == null ? null : 'dès ${formaterFcfa(s.prixMinFcfa!)}';

    final tuiles = <Widget>[
      TuileService(
        icone: Icons.two_wheeler,
        libelle: moto.libelle,
        sousTitre: desPrix(moto),
        miseEnAvant: true,
        onTap: () => widget.onService(moto),
      ),
      TuileService(
        icone: Icons.directions_car_filled,
        libelle: voiture.libelle,
        sousTitre: desPrix(voiture),
        onTap: () => widget.onService(voiture),
      ),
      TuileService(
        icone: Icons.inventory_2_outlined,
        libelle: 'Colis',
        couleurIcone: TaamaColors.primary,
        onTap: widget.onColis,
      ),
      TuileService(
        icone: Icons.event_outlined,
        libelle: 'Réserver',
        onTap: widget.onReserver,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < tuiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _apparition(0.45 + i * 0.07, tuiles[i])),
        ],
      ],
    );
  }
}

// ─── Petits widgets privés ───

class _BoutonRond extends StatelessWidget {
  const _BoutonRond({required this.icone, required this.info, required this.onPressed});

  final IconData icone;
  final String info;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: TaamaColors.textPrimary,
      child: IconButton(
        tooltip: info,
        onPressed: onPressed,
        icon: Icon(icone, color: TaamaColors.primary),
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }
}

/// Zoom de la carte : + et − dans une même capsule blanche.
class _CommandesZoom extends StatelessWidget {
  const _CommandesZoom({required this.onPlus, required this.onMoins});

  final VoidCallback onPlus;
  final VoidCallback onMoins;

  @override
  Widget build(BuildContext context) {
    Widget bouton(IconData icone, String info, VoidCallback action) => IconButton(
          tooltip: info,
          onPressed: action,
          icon: Icon(icone, color: TaamaColors.navy, size: 22),
          constraints: const BoxConstraints.tightFor(width: _largeurBoutons, height: 44),
        );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_largeurBoutons / 2),
      elevation: 4,
      shadowColor: TaamaColors.textPrimary,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          bouton(Icons.add_rounded, 'Zoomer', onPlus),
          Container(width: 22, height: 1, color: TaamaColors.border),
          bouton(Icons.remove_rounded, 'Dézoomer', onMoins),
        ],
      ),
    );
  }
}

/// Bandeau « course en cours » : rouvre le suivi. Bien visible, animé d'un
/// léger battement pour attirer l'œil (coupé si animations réduites).
class _BanniereCourseActive extends StatelessWidget {
  const _BanniereCourseActive({required this.course, required this.onTap});

  final CourseActive course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.navy,
      borderRadius: BorderRadius.circular(TaamaRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              AnimeEnBoucle(
                duree: const Duration(milliseconds: 900),
                builder: (context, t, child) => Opacity(opacity: 1 - 0.6 * t, child: child),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: TaamaColors.primary,
                    borderRadius: BorderRadius.circular(TaamaRadius.md),
                  ),
                  child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.libelleEtat,
                        style: TaamaText.body.copyWith(
                            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      'Vers ${course.destination}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TaamaText.body.copyWith(
                          color: TaamaColors.onNavyMuted, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: TaamaColors.primary,
                  borderRadius: BorderRadius.circular(TaamaRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Suivre',
                        style: TaamaText.body.copyWith(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.prenom, required this.urlPhoto, required this.onTap});

  final String? prenom;
  final String? urlPhoto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Mon compte',
      child: Material(
        color: TaamaColors.primary,
        shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
        elevation: 4,
        shadowColor: TaamaColors.textPrimary,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // PhotoAvatar gère déjà : https uniquement, repli sur les
          // initiales (URL R2 expirée, hors ligne), décodage à la bonne taille.
          child: PhotoAvatar(
            nom: prenom ?? '',
            urlPhoto: urlPhoto,
            diametre: 48,
            couleurFond: TaamaColors.primary,
            couleurTexte: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _PiluleDepart extends StatelessWidget {
  const _PiluleDepart({required this.libelle, required this.onTap});

  final String libelle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      elevation: 4,
      shadowColor: TaamaColors.textPrimary,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: TaamaColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.my_location_rounded, size: 16, color: TaamaColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DÉPART',
                        style: TaamaText.muted.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: TaamaColors.primary,
                        ),
                      ),
                      Text(
                        libelle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TaamaText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more_rounded, color: TaamaColors.navy),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PastilleSolde extends StatelessWidget {
  const _PastilleSolde({required this.soldeFcfa, required this.onTap});

  final int soldeFcfa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.navy,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                formaterFcfa(soldeFcfa),
                style: TaamaText.body.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PastilleProximite extends StatelessWidget {
  const _PastilleProximite({required this.texte, required this.actif, required this.onTap});

  final String texte;

  /// Au moins un chauffeur : le point clignote en vert.
  final bool actif;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.navy,
      borderRadius: BorderRadius.circular(20),
      elevation: 6,
      shadowColor: TaamaColors.textPrimary,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap == null ? null : () => onTap!(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimeEnBoucle(
                  duree: const Duration(milliseconds: 800),
                  builder: (context, t, child) => Opacity(opacity: 1 - 0.75 * t, child: child),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: actif ? TaamaColors.accentMint : TaamaColors.onNavyMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    texte,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TaamaText.body.copyWith(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarreRecherche extends StatelessWidget {
  const _BarreRecherche({required this.exemples, required this.onTap, required this.onDicter});

  final List<String> exemples;
  final VoidCallback onTap;
  final VoidCallback? onDicter;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.primarySoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 4),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: TaamaColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rechercher une destination',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TaamaText.body.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: TaamaColors.textSecondary,
                        ),
                      ),
                      if (exemples.isNotEmpty) _TexteDefilant(textes: exemples),
                    ],
                  ),
                ),
                if (onDicter != null)
                  IconButton(
                    tooltip: 'Dicter la destination',
                    onPressed: onDicter,
                    icon: const Icon(Icons.mic_none_rounded, color: TaamaColors.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fait défiler « ex. [lieu] » toutes les 3 s (fixe si animations réduites).
class _TexteDefilant extends StatefulWidget {
  const _TexteDefilant({required this.textes});

  final List<String> textes;

  @override
  State<_TexteDefilant> createState() => _TexteDefilantState();
}

class _TexteDefilantState extends State<_TexteDefilant> {
  Timer? _minuteur;
  int _indice = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _minuteur?.cancel();
    _minuteur = null;
    if (!MediaQuery.disableAnimationsOf(context) && widget.textes.length > 1) {
      _minuteur = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) setState(() => _indice++);
      });
    }
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texte = widget.textes[_indice % widget.textes.length];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: Text(
        'ex. $texte',
        key: ValueKey(_indice),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TaamaText.body.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: TaamaColors.primary,
        ),
      ),
    );
  }
}

class _BoutonPlusTard extends StatelessWidget {
  const _BoutonPlusTard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: TaamaColors.border, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 18, color: TaamaColors.primary),
                const SizedBox(width: 6),
                Text(
                  'Plus tard',
                  style: TaamaText.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: TaamaColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LieuxEnregistres extends StatelessWidget {
  const _LieuxEnregistres({
    required this.suggestions,
    required this.onSuggestion,
    required this.onAjouter,
  });

  final List<SuggestionDestination> suggestions;
  final ValueChanged<SuggestionDestination> onSuggestion;
  final VoidCallback onAjouter;

  static IconData _icone(TypeAdresse type) => switch (type) {
        TypeAdresse.domicile => Icons.home_rounded,
        TypeAdresse.travail => Icons.work_rounded,
        TypeAdresse.autre => Icons.place_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final s in suggestions) ...[
            _Puce(
              icone: _icone(s.type),
              texte: s.dureeMinutes == null ? s.libelle : '${s.libelle} · ${s.dureeMinutes} min',
              fond: TaamaColors.primarySoft,
              couleur: TaamaColors.primary,
              onTap: () => onSuggestion(s),
            ),
            const SizedBox(width: 8),
          ],
          _Puce(
            icone: Icons.add_rounded,
            texte: suggestions.isEmpty ? 'Ajouter Maison ou Travail' : 'Ajouter',
            fond: Colors.white,
            couleur: TaamaColors.primary,
            bordure: true,
            pastille: true,
            onTap: onAjouter,
          ),
        ],
      ),
    );
  }
}

class _Puce extends StatelessWidget {
  const _Puce({
    required this.icone,
    required this.texte,
    required this.fond,
    required this.couleur,
    required this.onTap,
    this.bordure = false,
    this.pastille = false,
  });

  final IconData icone;
  final String texte;
  final Color fond;
  final Color couleur;
  final VoidCallback onTap;
  final bool bordure;

  /// Icône blanche dans une pastille pleine (puce d'ajout).
  final bool pastille;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fond,
      shape: StadiumBorder(
        side: bordure
            ? const BorderSide(color: TaamaColors.border, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, maxWidth: 220),
          child: Padding(
            padding: EdgeInsets.only(left: pastille ? 8 : 14, right: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pastille)
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: couleur,
                      boxShadow: [
                        BoxShadow(
                          color: couleur.withValues(alpha: 0.30),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(icone, size: 18, color: TaamaColors.textOnDark),
                  )
                else
                  Icon(icone, size: 16, color: couleur),
                SizedBox(width: pastille ? 8 : 6),
                Flexible(
                  child: Text(
                    texte,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TaamaText.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: couleur,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CarteDerniereCourse extends StatelessWidget {
  const _CarteDerniereCourse({required this.course, required this.onTap});

  final DerniereCourse course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.primarySoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.history_rounded, color: TaamaColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Refaire votre dernière course',
                        style: TaamaText.muted.copyWith(fontSize: 12)),
                    Text(
                      course.destination,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TaamaText.body.copyWith(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (course.prixFcfa != null)
                Text(
                  formaterFcfa(course.prixFcfa!),
                  style: TaamaText.title.copyWith(fontSize: 15, color: TaamaColors.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandeauEspeces extends StatelessWidget {
  const _BandeauEspeces();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: TaamaColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          AnimeEnBoucle(
            duree: const Duration(milliseconds: 1500),
            builder: (context, t, child) =>
                Transform.translate(offset: Offset(0, -4 * t), child: child),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: TaamaColors.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.payments_outlined, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ton prix, accepté avant la course · payé en espèces',
                  style: TaamaText.title.copyWith(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Vous connaissez le prix avant de partir.',
                  style: TaamaText.body.copyWith(color: TaamaColors.onNavyMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
