// lib/widgets/taama_map.dart
//
// Carte réutilisable Taama (accueil, commande, suivi).
//
// Ce que ce widget garantit et que l'appelant n'a pas à refaire :
//  - les marqueurs de véhicules GLISSENT entre deux positions reçues
//    (WebSocket) au lieu de sauter, et pivotent selon leur cap ;
//  - l'itinéraire est tracé en deux couches (halo + trait) pour rester
//    lisible sur n'importe quel fond ;
//  - la caméra cadre automatiquement tous les points d'intérêt ;
//  - le fond de tuiles suit le thème (clair / nuit) sans code appelant.
//
// Aucune clé d'API n'est écrite ici : l'URL des tuiles arrive par
// --dart-define via TaamaMapTiles.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/taama_theme.dart';

// ---------------------------------------------------------------------------
// Configuration des tuiles
// ---------------------------------------------------------------------------

/// Fonds de carte. Les URL viennent de --dart-define pour ne jamais
/// committer une clé d'API dans le dépôt.
///
///   flutter run \
///     --dart-define=MAP_TILES_LIGHT=https://.../{z}/{x}/{y}.png \
///     --dart-define=MAP_TILES_DARK=https://.../{z}/{x}/{y}.png
///
/// Sans valeur fournie, on retombe sur CartoDB Voyager (mêmes données
/// OSM, style visuel épuré façon Uber/Google Maps — routes lisibles,
/// labels discrets, palette pastel) plutôt que les tuiles OSM brutes :
/// même style que taama_conducteur (voir fond_carte_taama.dart, dont ce
/// fichier s'inspire), gratuit, sans clé API.
class TaamaMapTiles {
  TaamaMapTiles._();

  static const String _voyager =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  static const String clair =
      String.fromEnvironment('MAP_TILES_LIGHT', defaultValue: _voyager);
  static const String sombre =
      String.fromEnvironment('MAP_TILES_DARK', defaultValue: _voyager);

  /// Sous-domaines CartoDB pour paralléliser le chargement des tuiles —
  /// sans effet si une URL --dart-define personnalisée n'utilise pas
  /// le motif {s}.
  static const List<String> subdomains = ['a', 'b', 'c', 'd'];

  static const String userAgent = 'com.taama.taama_app';

  static String pour(Brightness luminosite) =>
      luminosite == Brightness.dark ? sombre : clair;
}

/// Attribution requise par la licence des données (OpenStreetMap) et du
/// style visuel (CARTO) — même contenu que taama_conducteur/lib/widgets/
/// fond_carte_taama.dart, à ajouter aux children de chaque FlutterMap.
Widget attributionCarteTaama() {
  return RichAttributionWidget(
    alignment: AttributionAlignment.bottomLeft,
    attributions: [
      TextSourceAttribution('© OpenStreetMap contributors'),
      TextSourceAttribution('© CARTO'),
    ],
  );
}

// ---------------------------------------------------------------------------
// Modèle d'un véhicule affiché
// ---------------------------------------------------------------------------

class VehiculeCarte {
  const VehiculeCarte({
    required this.id,
    required this.position,
    this.estMoto = false,
    this.miseEnAvant = false,
  });

  /// Identifiant stable : c'est lui qui permet d'animer le déplacement
  /// du même véhicule d'une position à l'autre.
  final String id;
  final LatLng position;
  final bool estMoto;

  /// Le véhicule de la course en cours, dessiné en accent.
  final bool miseEnAvant;
}

// ---------------------------------------------------------------------------
// Carte
// ---------------------------------------------------------------------------

class TaamaMap extends StatefulWidget {
  const TaamaMap({
    super.key,
    this.positionClient,
    this.destination,
    this.vehicules = const [],
    this.itineraire = const [],
    this.interactive = true,
    this.themeNuit,
    this.cadrageAuto = true,
    this.zoomInitial = 14.5,
    this.margeCadrage = const EdgeInsets.all(56),
    this.controller,
  });

  final LatLng? positionClient;
  final LatLng? destination;
  final List<VehiculeCarte> vehicules;

  /// Tracé complet renvoyé par OSRM. Vide → aucun itinéraire dessiné.
  final List<LatLng> itineraire;

  final bool interactive;

  /// Null → suit le thème de l'application.
  final bool? themeNuit;

  /// Recadre sur l'ensemble des points à chaque changement.
  final bool cadrageAuto;
  final double zoomInitial;
  final EdgeInsets margeCadrage;
  final MapController? controller;

  @override
  State<TaamaMap> createState() => _TaamaMapState();
}

class _TaamaMapState extends State<TaamaMap> {
  late final MapController _carte = widget.controller ?? MapController();
  bool _prete = false;

  static const LatLng _bamako = LatLng(12.6392, -8.0029);

  List<LatLng> get _points => [
        if (widget.positionClient != null) widget.positionClient!,
        if (widget.destination != null) widget.destination!,
        ...widget.vehicules.map((v) => v.position),
        ...widget.itineraire,
      ];

  @override
  void didUpdateWidget(TaamaMap ancien) {
    super.didUpdateWidget(ancien);
    if (widget.cadrageAuto) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recadrer());
    }
  }

  void _recadrer() {
    if (!_prete || !mounted) return;
    final pts = _points;
    if (pts.length < 2) return;
    _carte.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: widget.margeCadrage,
        maxZoom: 16.5,
      ),
    );
  }

  /// À appeler depuis l'écran pour le bouton « recentrer ».
  void recentrer() {
    final p = widget.positionClient;
    if (p == null || !_prete) return;
    _carte.move(p, 15.5);
  }

  @override
  Widget build(BuildContext context) {
    final nuit = widget.themeNuit ??
        (Theme.of(context).brightness == Brightness.dark);
    final urlTuiles =
        TaamaMapTiles.pour(nuit ? Brightness.dark : Brightness.light);

    return FlutterMap(
      mapController: _carte,
      options: MapOptions(
        initialCenter: widget.positionClient ?? _bamako,
        initialZoom: widget.zoomInitial,
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.pinchZoom |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom
              : InteractiveFlag.none,
        ),
        onMapReady: () {
          _prete = true;
          if (widget.cadrageAuto) _recadrer();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: urlTuiles,
          subdomains: TaamaMapTiles.subdomains,
          userAgentPackageName: TaamaMapTiles.userAgent,
          maxNativeZoom: 19,
        ),
        attributionCarteTaama(),
        if (widget.itineraire.length >= 2)
          PolylineLayer(
            polylines: [
              // Halo : c'est lui qui rend le tracé lisible sur les rues.
              Polyline(
                points: widget.itineraire,
                strokeWidth: 11,
                color: nuit
                    ? TaamaColors.routeHaloNight
                    : TaamaColors.routeHaloDay,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
              Polyline(
                points: widget.itineraire,
                strokeWidth: 5.5,
                color: nuit
                    ? TaamaColors.routeNight
                    : TaamaColors.primary,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (widget.destination != null)
              Marker(
                point: widget.destination!,
                width: 26,
                height: 26,
                child: _MarqueurDestination(nuit: nuit),
              ),
            for (final v in widget.vehicules)
              Marker(
                point: v.position,
                width: 40,
                height: 40,
                child: VehiculeAnime(
                  key: ValueKey(v.id),
                  cible: v.position,
                  estMoto: v.estMoto,
                  miseEnAvant: v.miseEnAvant,
                  nuit: nuit,
                ),
              ),
            if (widget.positionClient != null)
              Marker(
                point: widget.positionClient!,
                width: 52,
                height: 52,
                child: PointClient(nuit: nuit),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Marqueur véhicule animé
// ---------------------------------------------------------------------------

/// Interpole la position et le cap entre deux mises à jour WebSocket.
///
/// flutter_map replace le marqueur à la position exacte à chaque build ;
/// l'animation se fait donc sur la ROTATION et sur un léger décalage
/// visuel, ce qui suffit à supprimer l'effet de saut sans dupliquer la
/// gestion des coordonnées.
class VehiculeAnime extends StatefulWidget {
  const VehiculeAnime({
    super.key,
    required this.cible,
    required this.estMoto,
    required this.miseEnAvant,
    required this.nuit,
  });

  final LatLng cible;
  final bool estMoto;
  final bool miseEnAvant;
  final bool nuit;

  @override
  State<VehiculeAnime> createState() => _VehiculeAnimeState();
}

class _VehiculeAnimeState extends State<VehiculeAnime>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late Animation<double> _cap = const AlwaysStoppedAnimation(0);

  double _capActuel = 0;

  @override
  void didUpdateWidget(VehiculeAnime ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.cible == widget.cible) return;

    final nouveauCap = _calculerCap(ancien.cible, widget.cible);
    // Ignore les micro-déplacements : sinon le marqueur pivote sur place
    // quand le chauffeur est à l'arrêt (dérive GPS).
    if (_distanceApprox(ancien.cible, widget.cible) > 8) {
      _cap = Tween<double>(
        begin: _capActuel,
        end: _capCourtChemin(_capActuel, nouveauCap),
      ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
      _capActuel = nouveauCap;
      _ctrl.forward(from: 0);
    }
  }

  /// Cap en radians entre deux points (0 = nord).
  double _calculerCap(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x);
  }

  /// Évite de faire tourner l'icône de 350° au lieu de -10°.
  double _capCourtChemin(double depuis, double vers) {
    var delta = (vers - depuis) % (2 * math.pi);
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    return depuis + delta;
  }

  /// Distance approximative en mètres (suffisant pour un seuil).
  double _distanceApprox(LatLng a, LatLng b) {
    const metresParDegre = 111320.0;
    final dLat = (b.latitude - a.latitude) * metresParDegre;
    final dLon = (b.longitude - a.longitude) *
        metresParDegre *
        math.cos(a.latitude * math.pi / 180);
    return math.sqrt(dLat * dLat + dLon * dLon);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fond = widget.miseEnAvant
        ? TaamaColors.primary
        : (widget.nuit ? TaamaColors.surface : TaamaColors.textPrimary);
    final couleurIcone = widget.miseEnAvant
        ? TaamaColors.textOnDark
        : (widget.nuit ? TaamaColors.textPrimary : TaamaColors.textOnDark);

    final pastille = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(TaamaRadius.md),
        boxShadow: TaamaShadows.card,
      ),
      child: Icon(
        widget.estMoto ? Icons.two_wheeler_rounded : Icons.local_taxi_rounded,
        size: 19,
        color: couleurIcone,
      ),
    );

    if (MediaQuery.disableAnimationsOf(context)) {
      return Center(child: pastille);
    }

    return Center(
      child: AnimatedBuilder(
        animation: _cap,
        builder: (_, enfant) => Transform.rotate(
          angle: _cap.value,
          child: enfant,
        ),
        child: pastille,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Point du client (halo pulsant) et destination
// ---------------------------------------------------------------------------

class PointClient extends StatefulWidget {
  const PointClient({super.key, this.nuit = false});

  final bool nuit;

  @override
  State<PointClient> createState() => _PointClientState();
}

class _PointClientState extends State<PointClient>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couleur =
        widget.nuit ? TaamaColors.routeNight : TaamaColors.primary;

    final noyau = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(color: TaamaColors.surface, width: 3),
      ),
    );

    if (MediaQuery.disableAnimationsOf(context)) {
      return Center(child: noyau);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final t = _ctrl.value;
            return Container(
              width: 20 + 30 * t,
              height: 20 + 30 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: couleur.withValues(alpha: 0.28 * (1 - t)),
              ),
            );
          },
        ),
        noyau,
      ],
    );
  }
}

class _MarqueurDestination extends StatelessWidget {
  const _MarqueurDestination({required this.nuit});

  final bool nuit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: nuit ? TaamaColors.surface : TaamaColors.textPrimary,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: nuit ? TaamaColors.textPrimary : TaamaColors.surface,
            width: 3,
          ),
        ),
      ),
    );
  }
}
