import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../carte/fond_carte.dart';
import '../../../theme/taama_theme.dart';
import '../../../widgets/couche_carte_taama.dart';
import '../chauffeur_proche.dart';
import '../couleurs_recherche.dart';
import 'avatar_chauffeur.dart';

/// Chauffeurs proches sur la vraie carte (fond, quartiers et attribution
/// Taama), autour du point de départ du devis, dans le rayon de la recherche.
/// Les positions sont celles du serveur, arrondies (grille d'environ 110 m) :
/// rien de plus précis n'est jamais affiché.
class CarteChauffeurs extends StatefulWidget {
  const CarteChauffeurs({
    super.key,
    required this.chauffeurs,
    required this.selectionne,
    required this.centre,
    required this.rayonM,
    required this.nuit,
    required this.onSelection,
    this.marges = EdgeInsets.zero,
  });

  final List<ChauffeurProche> chauffeurs;
  final ChauffeurProche? selectionne;

  /// Point de départ du devis : centre du cercle de recherche.
  final GeoPoint centre;
  final int rayonM;
  final bool nuit;
  final ValueChanged<ChauffeurProche> onSelection;

  /// Parties de la carte couvertes par l'en-tête (haut) et le panneau (bas) :
  /// le cercle de recherche est cadré entre elles, l'attribution reste visible.
  final EdgeInsets marges;

  @override
  State<CarteChauffeurs> createState() => _CarteChauffeursState();
}

class _CarteChauffeursState extends State<CarteChauffeurs> {
  final MapController _carte = MapController();
  bool _prete = false;

  static LatLng _point(GeoPoint p) => LatLng(p.lat, p.lng);

  /// Carré qui englobe le cercle de recherche, entre l'en-tête et le panneau.
  CameraFit get _cadrage {
    final centre = widget.centre;
    final dLat = widget.rayonM / 110540;
    final dLng = widget.rayonM / (111320 * math.cos(centre.lat * math.pi / 180));
    return CameraFit.bounds(
      bounds: LatLngBounds(
        LatLng(centre.lat - dLat, centre.lng - dLng),
        LatLng(centre.lat + dLat, centre.lng + dLng),
      ),
      padding: widget.marges + const EdgeInsets.all(16),
    );
  }

  @override
  void didUpdateWidget(CarteChauffeurs ancien) {
    super.didUpdateWidget(ancien);
    if (_prete &&
        (ancien.rayonM != widget.rayonM ||
            ancien.centre != widget.centre ||
            ancien.marges != widget.marges)) {
      _carte.fitCamera(_cadrage);
    }
  }

  @override
  void dispose() {
    _carte.dispose();
    super.dispose();
  }

  Marker _marqueur(ChauffeurProche chauffeur, {required bool selectionne}) {
    return Marker(
      point: _point(chauffeur.position),
      width: 56,
      height: 56,
      child: _Marqueur(
        chauffeur: chauffeur,
        selectionne: selectionne,
        onTap: () => widget.onSelection(chauffeur),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.selectionne;
    final margeAttribution =
        EdgeInsets.fromLTRB(8, 8, 8, widget.marges.bottom + 6);
    return FlutterMap(
      mapController: _carte,
      options: MapOptions(
        initialCameraFit: _cadrage,
        backgroundColor:
            widget.nuit ? TaamaColors.mapNight : TaamaColors.mapPlaceholder,
        // Plein nord : la rotation retournait les noms de rue (tuiles raster).
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () => _prete = true,
      ),
      children: [
        FondCarteTaama(nuit: widget.nuit),
        CoucheCarteTaama(
          nuit: widget.nuit,
          reserves: [
            ZoneReservee.attribution(
              alignement: Alignment.bottomLeft,
              marge: margeAttribution,
            ),
          ],
        ),
        CircleLayer(
          circles: [
            CircleMarker(
              point: _point(widget.centre),
              radius: widget.rayonM.toDouble(),
              useRadiusInMeter: true,
              color: TaamaColors.primary.withValues(alpha: 0.06),
              borderColor: TaamaColors.primary.withValues(alpha: 0.35),
              borderStrokeWidth: 1.5,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _point(widget.centre),
              width: 34,
              height: 34,
              child: const _PointDepart(),
            ),
            for (final chauffeur in widget.chauffeurs)
              if (chauffeur.id != selection?.id)
                _marqueur(chauffeur, selectionne: false),
            // Le chauffeur choisi en dernier : dessiné par-dessus les autres.
            if (selection != null) _marqueur(selection, selectionne: true),
          ],
        ),
        if (selection != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _point(selection.position),
                width: 240,
                height: 64,
                alignment: Alignment.topCenter,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _Bulle(chauffeur: selection),
                ),
              ),
            ],
          ),
        // TOUJOURS en dernier : rien ne doit la recouvrir.
        AttributionCarteTaama(
          nuit: widget.nuit,
          alignement: Alignment.bottomLeft,
          marge: margeAttribution,
        ),
      ],
    );
  }
}

class _Marqueur extends StatelessWidget {
  const _Marqueur({
    required this.chauffeur,
    required this.selectionne,
    required this.onTap,
  });

  final ChauffeurProche chauffeur;
  final bool selectionne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final estMoto = chauffeur.typeVehicule == TypeVehicule.moto;
    final couleur = CouleursRecherche.vehicule(chauffeur.typeVehicule);
    final sansAnimation = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      selected: selectionne,
      label: '${chauffeur.nomAffiche}, ${estMoto ? 'moto' : 'voiture'}, '
          '${chauffeur.etaMin} min',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedScale(
            scale: selectionne ? 1.0 : 0.78,
            duration: sansAnimation
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: couleur,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: selectionne
                        ? couleur.withValues(alpha: 0.55)
                        : TaamaColors.ombreMarqueur,
                    blurRadius: selectionne ? 16 : 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                estMoto ? Icons.two_wheeler : Icons.directions_car_filled,
                size: 22,
                color: estMoto ? TaamaColors.textPrimary : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prénom et temps d'approche du chauffeur choisi, au-dessus de son marqueur.
class _Bulle extends StatelessWidget {
  const _Bulle({required this.chauffeur});

  final ChauffeurProche chauffeur;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        decoration: BoxDecoration(
          color: TaamaColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: TaamaShadows.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarChauffeur(chauffeur: chauffeur, taille: 26, badge: false),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                chauffeur.prenom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: TaamaColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${chauffeur.etaMin} min',
              maxLines: 1,
              style: const TextStyle(
                color: TaamaColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Point de prise en charge (départ du devis), fixe : ce n'est pas forcément
/// la position actuelle du client.
class _PointDepart extends StatelessWidget {
  const _PointDepart();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Point de départ',
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: TaamaColors.surface,
          boxShadow: TaamaShadows.card,
        ),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: TaamaColors.primary,
          ),
        ),
      ),
    );
  }
}
