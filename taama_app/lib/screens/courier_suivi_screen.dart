// DESIGN_V4
//
// Suivi d'une livraison (côté client).
//
// Inchangé : position du livreur en direct (LocationService.ecouterPosition
// sur room_gps), statut relu toutes les 5 s (detailCourier), paiement
// portefeuille (payerCourier) quand le serveur l'autorise, chat room_chat.
//
// Nouveau :
// - carte plein haut, cadrée sur collecte + livraison, plein nord ; la carte
//   suit le livreur tant que le client ne la déplace pas (bouton Recentrer) ;
// - état « Recherche d'un livreur » avec radar animé ;
// - carte du livreur (initiales, véhicule, note) + bouton message ;
// - étapes animées, écran de fin « Colis livré », bandeau si annulé ;
// - relecture du statut en pause quand l'app est en arrière-plan (data) ;
// - quitter pendant une livraison active demande confirmation ;
// - bouton Payer seulement si le paiement in-app est actif.
//
// Correction : l'initiale du livreur plantait si son nom était vide.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../carte/fond_carte.dart';
import '../services/api_service.dart';
import '../services/config_app.dart';
import '../services/courses_en_cours.dart';
import '../services/location_service.dart';
import '../theme/taama_theme.dart';
import '../utils/format.dart';
import '../widgets/couche_carte_taama.dart';
import '../widgets/photo_avatar.dart';
import 'chat_screen.dart';
import 'courier_screen.dart';

const Set<String> _statutsActifs = {'en_recherche', 'livreur_assigne', 'en_collecte', 'en_livraison'};

class EcranSuiviCourier extends StatefulWidget {
  const EcranSuiviCourier({
    super.key,
    required this.commande,
    required this.pointCollecte,
    required this.pointLivraison,
    required this.adresseCollecte,
    required this.adresseLivraison,
  });

  final Map<String, dynamic> commande;
  final LatLng pointCollecte;
  final LatLng pointLivraison;
  final String adresseCollecte;
  final String adresseLivraison;

  @override
  State<EcranSuiviCourier> createState() => _EcranSuiviCourierState();
}

class _EcranSuiviCourierState extends State<EcranSuiviCourier>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late Map<String, dynamic> _commande = widget.commande;
  final LocationService _locationService = LocationService();
  final MapController _carte = MapController();
  Timer? _timerPolling;
  LatLng? _positionLivreur;
  bool _cartePrete = false;
  bool _suivre = true;
  bool _enPaiement = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  int get _id => _commande['id'] as int;
  String get _statut => _commande['statut']?.toString() ?? '';
  bool get _actif => _statutsActifs.contains(_statut);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_actif) _demarrerSuivi();
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
    WidgetsBinding.instance.removeObserver(this);
    _suspendreSuivi();
    _pulse.dispose();
    _carte.dispose();
    super.dispose();
  }

  /// App en arrière-plan : on coupe la relecture du statut ET le WebSocket
  /// GPS (data + batterie) ; au retour, on relit le statut et on reprend.
  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    if (!_actif) return;
    if (etat == AppLifecycleState.resumed) {
      _rafraichir();
      _demarrerSuivi();
    } else if (etat == AppLifecycleState.paused) {
      _suspendreSuivi();
    }
  }

  // ─── Suivi ───

  bool _ecouteGps = false;

  void _demarrerSuivi() {
    if (!_ecouteGps) {
      final roomGps = _commande['room_gps']?.toString() ?? 'courier_gps_$_id';
      _locationService.ecouterPosition(roomGps, (lat, lng) {
        if (!mounted) return;
        final p = LatLng(lat, lng);
        setState(() => _positionLivreur = p);
        if (_suivre && _cartePrete) _carte.move(p, 15.5);
      });
      _ecouteGps = true;
    }
    _demarrerPolling();
  }

  void _suspendreSuivi() {
    _timerPolling?.cancel();
    _timerPolling = null;
    if (_ecouteGps) {
      _locationService.arreter();
      _ecouteGps = false;
    }
  }

  void _demarrerPolling() {
    _timerPolling?.cancel();
    _timerPolling = Timer.periodic(const Duration(seconds: 5), (_) => _rafraichir());
  }

  Future<void> _rafraichir() async {
    try {
      final detail = await ApiService.detailCourier(_id);
      if (!mounted) return;
      setState(() => _commande = detail);
      if (!_actif) _suspendreSuivi();
      // Livrée ou annulée : plus en cours pour la déconnexion.
      if (_statut.isNotEmpty && !_actif) unawaited(CoursesEnCours.effacerLivraison(_id));
    } catch (_) {
      // Réseau instable : on réessaie au prochain tick.
    }
  }

  Future<void> _payer() async {
    setState(() => _enPaiement = true);
    try {
      await ApiService.payerCourier(_id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paiement effectué depuis ton solde Taama')),
      );
      final detail = await ApiService.detailCourier(_id);
      if (!mounted) return;
      setState(() => _commande = detail);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _enPaiement = false);
    }
  }

  void _ouvrirChat(String titre) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EcranChat(
          roomName: _commande['room_chat']?.toString() ?? 'courier_$_id',
          titreConversation: titre,
        ),
      ),
    );
  }

  void _cadrer() {
    if (!_cartePrete) return;
    final points = [
      widget.pointCollecte,
      widget.pointLivraison,
      if (_positionLivreur != null) _positionLivreur!,
    ];
    _carte.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.fromLTRB(50, 110, 50, 40),
      maxZoom: 16,
    ));
  }

  void _recentrer() {
    setState(() => _suivre = true);
    final p = _positionLivreur;
    if (p != null && _cartePrete) {
      _carte.move(p, 15.5);
    } else {
      _cadrer();
    }
  }

  Future<bool> _confirmerSortie() async {
    if (!_actif) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter le suivi ?'),
        content: const Text(
          'La livraison continue, mais tu ne pourras pas rouvrir ce suivi '
          'depuis l’application pour le moment.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rester')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitter')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _quitter() async {
    if (await _confirmerSortie() && mounted) Navigator.pop(context);
  }

  // ─── Construction ───

  @override
  Widget build(BuildContext context) {
    final haut = MediaQuery.paddingOf(context).top;
    return PopScope(
      canPop: !_actif,
      onPopInvokedWithResult: (aQuitte, _) {
        if (!aQuitte) _quitter();
      },
      child: Scaffold(
        backgroundColor: TaamaColors.background,
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _carte,
                    options: MapOptions(
                      initialCenter: widget.pointCollecte,
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                      onMapReady: () {
                        _cartePrete = true;
                        _cadrer();
                      },
                      onPositionChanged: (camera, parGeste) {
                        if (parGeste && _suivre) setState(() => _suivre = false);
                      },
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
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [widget.pointCollecte, widget.pointLivraison],
                            color: TaamaColors.primary.withValues(alpha: 0.6),
                            strokeWidth: 3,
                            pattern: StrokePattern.dashed(segments: const [8, 6]),
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: widget.pointCollecte,
                            width: 36,
                            height: 36,
                            child: const _Pastille(couleur: TaamaColors.navy, icone: Icons.inventory_2_rounded),
                          ),
                          Marker(
                            point: widget.pointLivraison,
                            width: 36,
                            height: 36,
                            child: const _Pastille(couleur: TaamaColors.primary, icone: Icons.flag_rounded),
                          ),
                          if (_positionLivreur != null)
                            Marker(
                              point: _positionLivreur!,
                              width: 70,
                              height: 70,
                              child: _MarqueurLivreur(pulse: _pulse),
                            ),
                        ],
                      ),
                      const AttributionCarteTaama(
                        alignement: Alignment.bottomLeft,
                        marge: EdgeInsets.all(8),
                      ),
                    ],
                  ),
                  Positioned(
                    top: haut + 10,
                    left: 12,
                    child: _BoutonRond(icone: Icons.arrow_back_rounded, info: 'Retour', onTap: _quitter),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 16,
                    child: AnimatedScale(
                      scale: _suivre ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutBack,
                      child: _BoutonRond(icone: Icons.my_location_rounded, info: 'Recentrer', onTap: _recentrer),
                    ),
                  ),
                ],
              ),
            ),
            _panneau(),
          ],
        ),
      ),
    );
  }

  (String, String, IconData, Color) get _infoStatut => switch (_statut) {
        'en_recherche' => ('Recherche d’un livreur', 'On contacte les livreurs proches…', Icons.radar_rounded, TaamaColors.warning),
        'livreur_assigne' => ('Livreur trouvé', 'Il se prépare à partir', Icons.how_to_reg_rounded, TaamaColors.primary),
        'en_collecte' => ('Le livreur arrive', 'Il va récupérer le colis', Icons.two_wheeler_rounded, TaamaColors.primary),
        'en_livraison' => ('Colis en route', 'Il roule vers le destinataire', Icons.local_shipping_rounded, TaamaColors.navy),
        'livre' => ('Colis livré', 'La livraison est terminée', Icons.verified_rounded, TaamaColors.success),
        'annule' => ('Livraison annulée', 'Le colis n’a pas été livré', Icons.cancel_rounded, TaamaColors.danger),
        _ => ('Livraison', '', Icons.inventory_2_rounded, TaamaColors.textSecondary),
      };

  Widget _panneau() {
    final (titre, sousTitre, icone, couleur) = _infoStatut;
    final livreur = _commande['livreur'];
    final duree = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 300);

    return Container(
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(TaamaRadius.xl + 4)),
        boxShadow: TaamaShadows.floating,
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Statut
                AnimatedSwitcher(
                  duration: duree,
                  transitionBuilder: (enfant, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(a),
                      child: enfant,
                    ),
                  ),
                  child: Row(
                    key: ValueKey(_statut),
                    children: [
                      _statut == 'en_recherche'
                          ? _Radar(pulse: _pulse, couleur: couleur)
                          : Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: couleur.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(TaamaRadius.lg),
                              ),
                              child: Icon(icone, color: couleur, size: 28),
                            ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(titre, style: TaamaText.title.copyWith(fontSize: 20)),
                            if (sousTitre.isNotEmpty) Text(sousTitre, style: TaamaText.muted),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Etapes(statut: _statut, duree: duree),

                // Livreur
                if (livreur is Map && _statut != 'annule') ...[
                  const SizedBox(height: 16),
                  _carteLivreur(livreur),
                ],

                // Trajet
                const SizedBox(height: 14),
                _ligneAdresse(Icons.inventory_2_rounded, TaamaColors.navy, widget.adresseCollecte),
                const SizedBox(height: 8),
                _ligneAdresse(Icons.flag_rounded, TaamaColors.primary, widget.adresseLivraison),

                // Prix
                const SizedBox(height: 14),
                _lignePrix(),

                if (_commande['photo_livraison'] == true) ...[
                  const SizedBox(height: 12),
                  _bandeau(Icons.photo_camera_rounded, 'Photo de remise enregistrée par le livreur', TaamaColors.success),
                ],

                // Paiement : autorisé par le serveur ET paiement in-app actif.
                ValueListenableBuilder<bool>(
                  valueListenable: ConfigApp.paiementActif,
                  builder: (context, paiementActif, _) {
                    if (!(paiementActif && _commande['peut_payer'] == true)) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _enPaiement ? null : _payer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TaamaColors.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TaamaRadius.lg)),
                          ),
                          child: _enPaiement
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  'Payer ${formaterFcfa((num.tryParse('${_commande['prix']}') ?? 0).round())}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                        ),
                      ),
                    );
                  },
                ),

                if (!_actif) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TaamaRadius.lg)),
                          ),
                          child: const Text('Terminer'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const EcranCourier()),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TaamaColors.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TaamaRadius.lg)),
                          ),
                          child: const Text('Nouvel envoi', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _carteLivreur(Map livreur) {
    final nom = livreur['nom']?.toString().trim() ?? '';
    final vehicule = livreur['vehicule']?.toString().trim() ?? '';
    final note = livreur['note']?.toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TaamaColors.surfaceMuted,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
      ),
      child: Row(
        children: [
          PhotoAvatar(
            nom: nom.isEmpty ? 'Livreur' : nom,
            diametre: 46,
            couleurFond: TaamaColors.navy,
            couleurTexte: Colors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nom.isEmpty ? 'Ton livreur' : nom,
                    style: TaamaText.body.copyWith(fontWeight: FontWeight.w800)),
                Row(
                  children: [
                    if (vehicule.isNotEmpty)
                      Flexible(
                        child: Text(vehicule, overflow: TextOverflow.ellipsis, style: TaamaText.muted.copyWith(fontSize: 12)),
                      ),
                    if (note != null && note.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.star_rounded, size: 14, color: TaamaColors.star),
                      Text(note, style: TaamaText.muted.copyWith(fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (_actif)
            Material(
              color: TaamaColors.primary,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Écrire au livreur',
                onPressed: () => _ouvrirChat(nom.isEmpty ? 'Livreur' : nom),
                icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ligneAdresse(IconData icone, Color couleur, String adresse) {
    return Row(
      children: [
        Icon(icone, size: 18, color: couleur),
        const SizedBox(width: 10),
        Expanded(
          child: Text(adresse, maxLines: 1, overflow: TextOverflow.ellipsis, style: TaamaText.body.copyWith(fontSize: 13)),
        ),
      ],
    );
  }

  Widget _lignePrix() {
    final prix = num.tryParse('${_commande['prix']}');
    final paye = _commande['paye'] == true;
    return Row(
      children: [
        Expanded(
          child: Text(
            prix == null ? '—' : formaterFcfa(prix.round()),
            style: TaamaText.title.copyWith(fontSize: 20),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: ConfigApp.paiementActif,
          builder: (context, paiementActif, _) {
            final (libelle, couleur) = paye
                ? ('Payé', TaamaColors.success)
                : (paiementActif ? ('À payer', TaamaColors.warning) : ('En espèces', TaamaColors.primary));
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(TaamaRadius.pill),
              ),
              child: Text(libelle, style: TextStyle(color: couleur, fontWeight: FontWeight.w800, fontSize: 12)),
            );
          },
        ),
      ],
    );
  }

  Widget _bandeau(IconData icone, String texte, Color couleur) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(TaamaRadius.md),
      ),
      child: Row(
        children: [
          Icon(icone, color: couleur, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(texte, style: TextStyle(color: couleur, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

// ─── Widgets ───

class _Etapes extends StatelessWidget {
  const _Etapes({required this.statut, required this.duree});
  final String statut;
  final Duration duree;

  static const _etapes = ['livreur_assigne', 'en_collecte', 'en_livraison', 'livre'];
  static const _libelles = ['Livreur', 'Collecte', 'En route', 'Livré'];

  @override
  Widget build(BuildContext context) {
    final index = _etapes.indexOf(statut);
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < _etapes.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < _etapes.length - 1 ? 6 : 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: i <= index ? 1 : 0),
                      duration: duree,
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 5,
                        backgroundColor: TaamaColors.border,
                        color: statut == 'livre' ? TaamaColors.success : TaamaColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < _libelles.length; i++)
              Expanded(
                child: Text(
                  _libelles[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == index ? FontWeight.w900 : FontWeight.w600,
                    color: i <= index ? TaamaColors.textPrimary : TaamaColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Radar extends StatelessWidget {
  const _Radar({required this.pulse, required this.couleur});
  final Animation<double> pulse;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          Widget onde(double decalage) {
            final t = (pulse.value + decalage) % 1;
            return Opacity(
              opacity: (1 - t) * 0.7,
              child: Container(
                width: 18 + 34 * t,
                height: 18 + 34 * t,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: couleur, width: 2)),
              ),
            );
          }

          return Stack(alignment: Alignment.center, children: [onde(0), onde(0.5), child!]);
        },
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _MarqueurLivreur extends StatelessWidget {
  const _MarqueurLivreur({required this.pulse});
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) => Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: (1 - pulse.value) * 0.5,
            child: Container(
              width: 36 + 34 * pulse.value,
              height: 36 + 34 * pulse.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TaamaColors.primary.withValues(alpha: 0.25),
              ),
            ),
          ),
          child!,
        ],
      ),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: TaamaColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
        ),
        child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.couleur, required this.icone});
  final Color couleur;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Icon(icone, color: Colors.white, size: 17),
    );
  }
}

class _BoutonRond extends StatelessWidget {
  const _BoutonRond({required this.icone, required this.info, required this.onTap});
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
