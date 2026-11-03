// DESIGN_V4
//
// Choix d'un point de collecte / livraison, façon VTC : la carte bouge sous
// une épingle fixe au centre ; l'adresse du point (quartier, rue) s'affiche
// en bas, avec un champ « Repère » pour guider le livreur.
//
// Remplace l'ancien choix par appui sur la carte, qui renvoyait des
// coordonnées brutes (« 12.6392, -8.0029 ») comme adresse au livreur.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../carte/fond_carte.dart';
import '../theme/taama_theme.dart';
import '../widgets/couche_carte_taama.dart';

/// Point choisi : position + adresse lisible envoyée au serveur (255 max).
class PointCourier {
  final LatLng position;
  final String adresse;
  const PointCourier(this.position, this.adresse);
}

const LatLng _bamako = LatLng(12.6392, -8.0029);
const int _longueurMaxAdresse = 255;
const int _longueurMaxRepere = 80;

class EcranSelectionPointCourier extends StatefulWidget {
  const EcranSelectionPointCourier({
    super.key,
    required this.estCollecte,
    this.pointInitial,
  });

  final bool estCollecte;
  final PointCourier? pointInitial;

  @override
  State<EcranSelectionPointCourier> createState() => _EcranSelectionPointCourierState();
}

class _EcranSelectionPointCourierState extends State<EcranSelectionPointCourier>
    with SingleTickerProviderStateMixin {
  final MapController _carte = MapController();
  final TextEditingController _repere = TextEditingController();
  late LatLng _centre = widget.pointInitial?.position ?? _bamako;

  bool _enMouvement = false;
  bool _rechercheAdresse = false;
  String? _adresse; // libellé du quartier / de la rue
  Timer? _debounce;
  int _requete = 0; // ignore les réponses arrivées dans le désordre

  late final AnimationController _saut = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  Color get _couleur => widget.estCollecte ? TaamaColors.navy : TaamaColors.primary;

  @override
  void initState() {
    super.initState();
    if (widget.pointInitial != null) {
      _adresse = widget.pointInitial!.adresse;
    } else {
      _centrerSurMoi();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _repere.dispose();
    _saut.dispose();
    _carte.dispose();
    super.dispose();
  }

  Future<void> _centrerSurMoi() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _chercherAdresse(_centre);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      if (!mounted) return;
      final p = LatLng(pos.latitude, pos.longitude);
      setState(() => _centre = p);
      _carte.move(p, 16.5);
      _chercherAdresse(p);
    } catch (e) {
      if (kDebugMode) debugPrint('[Courier] Position indisponible : $e');
      _chercherAdresse(_centre);
    }
  }

  void _surMouvement(MapCamera camera, bool parGeste) {
    _centre = camera.center;
    if (parGeste && !_enMouvement) {
      setState(() {
        _enMouvement = true;
        _adresse = null;
      });
      _saut.forward();
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      if (_enMouvement) {
        setState(() => _enMouvement = false);
        _saut.reverse();
      }
      _chercherAdresse(_centre);
    });
  }

  /// Adresse lisible du point (quartier, rue) via Nominatim. En cas
  /// d'échec : libellé neutre, jamais de coordonnées brutes.
  Future<void> _chercherAdresse(LatLng p) async {
    final numero = ++_requete;
    setState(() => _rechercheAdresse = true);
    String libelle = 'Point choisi sur la carte';
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': p.latitude.toStringAsFixed(6),
        'lon': p.longitude.toStringAsFixed(6),
        'format': 'jsonv2',
        'zoom': '17',
        'accept-language': 'fr',
      });
      final rep = await http
          .get(uri, headers: {'User-Agent': AppConfig.userAgentHttp})
          .timeout(const Duration(seconds: 12));
      if (rep.statusCode == 200) {
        final donnees = jsonDecode(rep.body);
        final a = donnees is Map ? donnees['address'] : null;
        if (a is Map) {
          final morceaux = <String>[
            for (final cle in ['road', 'neighbourhood', 'quarter', 'suburb', 'city_district'])
              if (a[cle] is String && (a[cle] as String).trim().isNotEmpty) (a[cle] as String).trim(),
          ];
          // Sans doublons, 2 éléments max : « Rue 312, Hamdallaye ».
          final uniques = <String>[];
          for (final m in morceaux) {
            if (!uniques.contains(m)) uniques.add(m);
            if (uniques.length == 2) break;
          }
          if (uniques.isNotEmpty) libelle = uniques.join(', ');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Courier] Adresse introuvable : $e');
    }
    if (!mounted || numero != _requete) return;
    setState(() {
      _adresse = libelle;
      _rechercheAdresse = false;
    });
  }

  void _confirmer() {
    final base = _adresse ?? 'Point choisi sur la carte';
    final repere = _repere.text.trim();
    var complet = repere.isEmpty ? base : '$base — $repere';
    if (complet.length > _longueurMaxAdresse) {
      complet = complet.substring(0, _longueurMaxAdresse);
    }
    Navigator.pop(context, PointCourier(_centre, complet));
  }

  @override
  Widget build(BuildContext context) {
    final haut = MediaQuery.paddingOf(context).top;
    final pret = !_enMouvement && !_rechercheAdresse && _adresse != null;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _carte,
                  options: MapOptions(
                    initialCenter: _centre,
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onPositionChanged: _surMouvement,
                  ),
                  children: [
                    const FondCarteTaama(),
                    CoucheCarteTaama(
                      reserves: [
                        ZoneReservee.attribution(
                          alignement: Alignment.bottomLeft,
                          marge: const EdgeInsets.all(8),
                        ),
                      ],
                    ),
                    const AttributionCarteTaama(
                      alignement: Alignment.bottomLeft,
                      marge: EdgeInsets.all(8),
                    ),
                  ],
                ),

                // Épingle fixe au centre (se soulève pendant le déplacement)
                IgnorePointer(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _saut,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, -24 - 14 * _saut.value),
                        child: child,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _couleur,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: TaamaShadows.floating,
                            ),
                            child: Icon(
                              widget.estCollecte ? Icons.inventory_2_rounded : Icons.flag_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          Container(width: 3, height: 14, color: _couleur),
                        ],
                      ),
                    ),
                  ),
                ),
                // Ombre au sol
                IgnorePointer(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _saut,
                      builder: (context, _) => Container(
                        width: 14 - 6 * _saut.value,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),

                // Retour + titre
                Positioned(
                  top: haut + 10,
                  left: 12,
                  right: 12,
                  child: Row(
                    children: [
                      _BoutonRondCarte(
                        icone: Icons.arrow_back_rounded,
                        info: 'Retour',
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: TaamaColors.surface,
                            borderRadius: BorderRadius.circular(TaamaRadius.pill),
                            boxShadow: TaamaShadows.floating,
                          ),
                          child: Text(
                            widget.estCollecte ? 'Où récupérer le colis ?' : 'Où livrer le colis ?',
                            style: TaamaText.body.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Ma position
                Positioned(
                  right: 12,
                  bottom: 36,
                  child: _BoutonRondCarte(
                    icone: Icons.my_location_rounded,
                    info: 'Ma position',
                    onTap: _centrerSurMoi,
                  ),
                ),
              ],
            ),
          ),

          // Panneau bas
          Container(
            decoration: BoxDecoration(
              color: TaamaColors.surface,
              boxShadow: TaamaShadows.floating,
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _couleur.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(TaamaRadius.md),
                          ),
                          child: Icon(Icons.place_rounded, color: _couleur),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: (_enMouvement || _rechercheAdresse || _adresse == null)
                                ? Text(
                                    'Recherche de l’adresse…',
                                    key: const ValueKey('recherche'),
                                    style: TaamaText.muted,
                                  )
                                : Text(
                                    _adresse!,
                                    key: ValueKey(_adresse),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TaamaText.body.copyWith(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _repere,
                      maxLength: _longueurMaxRepere,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Repère : à côté de la pharmacie, portail bleu…',
                        prefixIcon: const Icon(Icons.edit_location_alt_rounded),
                        filled: true,
                        fillColor: TaamaColors.surfaceMuted,
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(TaamaRadius.md),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: pret ? _confirmer : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _couleur,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(TaamaRadius.lg),
                          ),
                        ),
                        child: Text(
                          widget.estCollecte ? 'Confirmer la collecte' : 'Confirmer la livraison',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoutonRondCarte extends StatelessWidget {
  const _BoutonRondCarte({required this.icone, required this.info, required this.onTap});
  final IconData icone;
  final String info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.surface,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black26,
      child: IconButton(
        tooltip: info,
        onPressed: onTap,
        icon: Icon(icone, color: TaamaColors.textPrimary),
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }
}
