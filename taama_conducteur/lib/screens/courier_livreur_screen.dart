// DESIGN_V4
//
// Livraison en cours (côté livreur).
//
// Inchangé : changerStatutCourier (mêmes appels, même photo base64 à la
// remise), salon GPS (room_gps) et chat (room_chat), fermeture à « livré ».
//
// Nouveau :
// - en-tête bleu nuit avec l'étape en cours, qui change en animation ;
// - frise verticale Collecte → Livraison avec le point actif qui pulse ;
// - bouton « Itinéraire » : Google Maps vers l'adresse de l'étape en cours
//   (collecte, puis livraison) ;
// - action principale en « Glisser pour confirmer » : plus de changement de
//   statut par un appui accidentel (irréversible côté serveur) ;
// - écran de succès animé à « livré » avant la fermeture ;
// - mode gratuit : « Espèces à encaisser » au lieu de « Non payé » ;
// - bandeau clair si la livraison a été annulée.
//
// Corrections :
// - le GPS n'est plus envoyé pour une livraison déjà livrée ou annulée ;
// - caméra refusée ou indisponible : message au lieu d'un crash ;
// - plus d'emojis dans l'interface.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/config_app.dart';
import '../services/location_service.dart';
import '../theme/couleurs_taama.dart';
import '../utils/format.dart';
import 'chat_screen.dart';

const Set<String> _statutsActifs = {'livreur_assigne', 'en_collecte', 'en_livraison'};

class EcranCourierLivreur extends StatefulWidget {
  final Map<String, dynamic> livraison;
  const EcranCourierLivreur({super.key, required this.livraison});

  @override
  State<EcranCourierLivreur> createState() => _EcranCourierLivreurState();
}

class _EcranCourierLivreurState extends State<EcranCourierLivreur>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _livraison;
  // Canal partagé de la livraison : tant qu'il est connecté, l'envoi HTTP
  // « en ligne » de la position est suspendu (LocationService).
  late final LocationService _locationService = LocationService.pourCourse(_salleGps);
  bool _enChargement = false;
  bool _gpsActif = false;
  bool _succes = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  String get _statut => _livraison['statut']?.toString() ?? '';

  String get _salleGps => _livraison['room_gps']?.toString() ?? 'courier_gps_${_livraison['id']}';

  @override
  void initState() {
    super.initState();
    _livraison = widget.livraison;
    // GPS seulement pour une livraison réellement en cours.
    if (_statutsActifs.contains(_statut)) {
      _locationService.demarrerEnvoiPosition(_salleGps);
      _gpsActif = true;
    }
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
    if (_gpsActif) _locationService.arreter();
    _pulse.dispose();
    super.dispose();
  }

  void _arreterGps() {
    if (!_gpsActif) return;
    _locationService.arreter();
    _gpsActif = false;
  }

  Future<void> _changerStatut({String? photoBase64}) async {
    setState(() => _enChargement = true);
    try {
      final res = await ApiService.changerStatutCourier(
        _livraison['id'] as int,
        photoLivraison: photoBase64,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _livraison = {..._livraison, 'statut': res['statut']});

      if (res['statut'] == 'livre') {
        _arreterGps();
        setState(() => _succes = true);
        // Laisse voir l'animation de succès, puis ferme.
        await Future.delayed(const Duration(milliseconds: 1600));
        if (mounted) Navigator.pop(context);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Étape enregistrée.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
  }

  Future<void> _prendrePhotoEtLivrer() async {
    final picker = ImagePicker();
    XFile? image;
    try {
      image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 800,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Impossible d'ouvrir la caméra. Vérifie les autorisations de l'application."),
      ));
      return;
    }
    if (image == null || !mounted) return;

    final bytes = await image.readAsBytes();
    final base64 = base64Encode(bytes);
    await _changerStatut(photoBase64: base64);
  }

  Future<void> _confirmerEtape() async {
    if (_enChargement) return;
    if (_statut == 'en_livraison') {
      await _prendrePhotoEtLivrer();
    } else {
      await _changerStatut();
    }
  }

  /// Adresse de l'étape en cours : collecte tant que le colis n'est pas
  /// récupéré, puis livraison.
  String get _adresseCible => _statut == 'en_livraison'
      ? (_livraison['adresse_livraison']?.toString() ?? '')
      : (_livraison['adresse_collecte']?.toString() ?? '');

  /// Coordonnées exactes de l'étape en cours (renvoyées par mes-livraisons),
  /// null si absentes.
  ({double lat, double lng})? get _coordonneesCible {
    final versLivraison = _statut == 'en_livraison';
    final lat = num.tryParse('${_livraison[versLivraison ? 'lat_livraison' : 'lat_collecte']}');
    final lng = num.tryParse('${_livraison[versLivraison ? 'lng_livraison' : 'lng_collecte']}');
    if (lat == null || lng == null) return null;
    return (lat: lat.toDouble(), lng: lng.toDouble());
  }

  /// Google Maps vers le point EXACT choisi par le client (coordonnées) ;
  /// l'adresse texte n'est qu'un repli, Google pouvant mal la comprendre.
  Future<void> _ouvrirItineraire() async {
    final c = _coordonneesCible;
    final adresse = _adresseCible.trim();
    if (c == null && adresse.isEmpty) return;
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': c != null
          ? '${c.lat.toStringAsFixed(6)},${c.lng.toStringAsFixed(6)}'
          : '$adresse, Bamako, Mali',
      'travelmode': 'driving',
    });
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[Livraison] Ouverture itinéraire impossible : $e');
    }
  }

  void _ouvrirChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EcranChat(
          roomName: _livraison['room_chat']?.toString() ?? 'courier_${_livraison['id']}',
          titreConversation: 'Client',
        ),
      ),
    );
  }

  // ─── Libellés ───

  static const _categories = {
    'colis': (Icons.inventory_2_rounded, 'Colis standard'),
    'repas': (Icons.restaurant_rounded, 'Repas (restaurant)'),
    'document': (Icons.description_rounded, 'Document officiel'),
  };

  (String, String, IconData) get _etape => switch (_statut) {
        'livreur_assigne' => ('Nouvelle livraison', 'Va récupérer le colis', Icons.assignment_turned_in_rounded),
        'en_collecte' => ('En route vers la collecte', "Récupère le colis chez l'expéditeur", Icons.two_wheeler_rounded),
        'en_livraison' => ('Livraison en cours', 'Remets le colis au destinataire', Icons.local_shipping_rounded),
        'livre' => ('Colis livré', 'Bravo, livraison terminée', Icons.verified_rounded),
        'annule' => ('Livraison annulée', "Tu n'as plus rien à faire", Icons.cancel_rounded),
        _ => ('Livraison', '', Icons.inventory_2_rounded),
      };

  String get _texteGlisser => switch (_statut) {
        'livreur_assigne' => 'Glisser pour partir collecter',
        'en_collecte' => 'Glisser : colis récupéré',
        'en_livraison' => 'Glisser : photo et livré',
        _ => '',
      };

  Color get _couleurAction => switch (_statut) {
        'livreur_assigne' => CouleursTaama.indigo,
        'en_collecte' => CouleursTaama.terreCuite,
        'en_livraison' => Colors.green.shade600,
        _ => Colors.grey,
      };

  // ─── Construction ───

  @override
  Widget build(BuildContext context) {
    final reduit = MediaQuery.disableAnimationsOf(context);
    final duree = reduit ? Duration.zero : const Duration(milliseconds: 350);
    final actif = _statutsActifs.contains(_statut);

    return PopScope(
      canPop: !_enChargement,
      child: Scaffold(
        backgroundColor: CouleursTaama.sable,
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _enTete(duree)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
                  sliver: SliverList.list(
                    children: [
                      if (_statut == 'annule') ...[
                        _bandeauAnnule(),
                        const SizedBox(height: 14),
                      ],
                      _carteTrajet(),
                      const SizedBox(height: 14),
                      if (actif) ...[
                        _actionsRapides(),
                        const SizedBox(height: 14),
                      ],
                      _carteColis(),
                    ],
                  ),
                ),
              ],
            ),

            // Action principale, fixée en bas
            if (actif)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4))],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: AnimatedSwitcher(
                        duration: duree,
                        child: _GlisserPourConfirmer(
                          key: ValueKey(_statut),
                          texte: _texteGlisser,
                          couleur: _couleurAction,
                          icone: _statut == 'en_livraison'
                              ? Icons.photo_camera_rounded
                              : Icons.arrow_forward_rounded,
                          enChargement: _enChargement,
                          onConfirme: _confirmerEtape,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Succès
            IgnorePointer(
              ignoring: !_succes,
              child: AnimatedOpacity(
                opacity: _succes ? 1 : 0,
                duration: duree,
                child: _succes ? const _EcranSucces() : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _enTete(Duration duree) {
    final (titre, sousTitre, icone) = _etape;
    final haut = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(8, haut + 4, 16, 24),
      decoration: const BoxDecoration(
        color: CouleursTaama.indigo,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Retour',
                onPressed: _enChargement ? null : () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              const Spacer(),
              if (_gpsActif)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => Opacity(
                          opacity: 0.4 + 0.6 * (1 - _pulse.value),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Position partagée',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: AnimatedSwitcher(
              duration: duree,
              transitionBuilder: (enfant, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0.1, 0), end: Offset.zero).animate(a),
                  child: enfant,
                ),
              ),
              child: Row(
                key: ValueKey(_statut),
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icone, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (sousTitre.isNotEmpty)
                          Text(
                            sousTitre,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: _Progression(statut: _statut, duree: duree),
          ),
        ],
      ),
    );
  }

  Widget _bandeauAnnule() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.red),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cette livraison a été annulée. Ne récupère pas le colis.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteTrajet() {
    final collecteFaite = _statut == 'en_livraison' || _statut == 'livre';
    final vaVersCollecte = _statut == 'livreur_assigne' || _statut == 'en_collecte';
    return _Carte(
      child: Column(
        children: [
          _PointTrajet(
            titre: 'Collecte',
            adresse: _livraison['adresse_collecte']?.toString() ?? '',
            couleur: CouleursTaama.indigo,
            icone: collecteFaite ? Icons.check_rounded : Icons.storefront_rounded,
            fait: collecteFaite,
            actif: vaVersCollecte,
            pulse: _pulse,
            afficherLigne: true,
          ),
          _PointTrajet(
            titre: 'Livraison',
            adresse: _livraison['adresse_livraison']?.toString() ?? '',
            couleur: CouleursTaama.terreCuite,
            icone: _statut == 'livre' ? Icons.check_rounded : Icons.flag_rounded,
            fait: _statut == 'livre',
            actif: _statut == 'en_livraison',
            pulse: _pulse,
            afficherLigne: false,
          ),
        ],
      ),
    );
  }

  Widget _actionsRapides() {
    return Row(
      children: [
        Expanded(
          child: _BoutonAction(
            icone: Icons.directions_rounded,
            texte: 'Itinéraire',
            sousTexte: _statut == 'en_livraison' ? 'vers la livraison' : 'vers la collecte',
            couleur: CouleursTaama.indigo,
            onTap: (_coordonneesCible == null && _adresseCible.trim().isEmpty) ? null : _ouvrirItineraire,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BoutonAction(
            icone: Icons.chat_bubble_rounded,
            texte: 'Message',
            sousTexte: 'au client',
            couleur: CouleursTaama.terreCuite,
            onTap: _ouvrirChat,
          ),
        ),
      ],
    );
  }

  Widget _carteColis() {
    final categorie = _categories[_livraison['categorie']] ?? _categories['colis']!;
    final description = _livraison['description_colis']?.toString().trim() ?? '';
    final prix = num.tryParse(_livraison['prix']?.toString() ?? '');
    final paye = _livraison['paye'] == true;

    return _Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: CouleursTaama.indigo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(categorie.$1, color: CouleursTaama.indigo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categorie.$2,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: CouleursTaama.indigo,
                      ),
                    ),
                    if (description.isNotEmpty)
                      Text(
                        description,
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: ConfigApp.paiementActif,
            builder: (context, paiementActif, _) {
              final (libelle, couleur, icone) = paye
                  ? ('Déjà payé', Colors.green.shade700, Icons.check_circle_rounded)
                  : paiementActif
                      ? ('Non payé', Colors.orange.shade800, Icons.schedule_rounded)
                      : ('Espèces à encaisser', CouleursTaama.terreCuite, Icons.payments_rounded);
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      prix == null ? '—' : formaterFcfa(prix.round()),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: CouleursTaama.indigo,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: couleur.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icone, size: 16, color: couleur),
                        const SizedBox(width: 4),
                        Text(
                          libelle,
                          style: TextStyle(color: couleur, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Widgets ───

class _Carte extends StatelessWidget {
  const _Carte({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

/// Barre 4 étapes dans l'en-tête : les segments se remplissent en animation.
class _Progression extends StatelessWidget {
  const _Progression({required this.statut, required this.duree});
  final String statut;
  final Duration duree;

  static const _etapes = ['livreur_assigne', 'en_collecte', 'en_livraison', 'livre'];
  static const _libelles = ['Assigné', 'Collecte', 'Livraison', 'Livré'];

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
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        color: i == index ? CouleursTaama.or : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < _libelles.length; i++)
              Expanded(
                child: Text(
                  _libelles[i],
                  style: TextStyle(
                    color: i == index
                        ? CouleursTaama.or
                        : (i < index ? Colors.white : Colors.white54),
                    fontSize: 11,
                    fontWeight: i == index ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Un point de la frise Collecte → Livraison.
class _PointTrajet extends StatelessWidget {
  const _PointTrajet({
    required this.titre,
    required this.adresse,
    required this.couleur,
    required this.icone,
    required this.fait,
    required this.actif,
    required this.pulse,
    required this.afficherLigne,
  });

  final String titre;
  final String adresse;
  final Color couleur;
  final IconData icone;
  final bool fait;
  final bool actif;
  final Animation<double> pulse;
  final bool afficherLigne;

  @override
  Widget build(BuildContext context) {
    final c = fait ? Colors.green.shade600 : couleur;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: AnimatedBuilder(
                    animation: pulse,
                    builder: (context, child) => Stack(
                      alignment: Alignment.center,
                      children: [
                        if (actif)
                          Opacity(
                            opacity: (1 - pulse.value) * 0.6,
                            child: Container(
                              width: 30 + 14 * pulse.value,
                              height: 30 + 14 * pulse.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                        child!,
                      ],
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: (fait || actif) ? c : c.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icone, size: 18, color: (fait || actif) ? Colors.white : c),
                    ),
                  ),
                ),
                if (afficherLigne)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: fait ? Colors.green.shade300 : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: afficherLigne ? 18 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w800,
                      color: actif ? c : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    adresse.isEmpty ? '—' : adresse,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: actif ? FontWeight.w800 : FontWeight.w600,
                      color: fait ? Colors.grey.shade500 : CouleursTaama.indigo,
                      decoration: fait ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoutonAction extends StatelessWidget {
  const _BoutonAction({
    required this.icone,
    required this.texte,
    required this.sousTexte,
    required this.couleur,
    required this.onTap,
  });

  final IconData icone;
  final String texte;
  final String sousTexte;
  final Color couleur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icone, color: couleur),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(texte,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: CouleursTaama.indigo)),
                    Text(sousTexte,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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

/// « Glisser pour confirmer » : évite qu'un appui accidentel fasse avancer
/// une étape irréversible. Un simple appui affiche un rappel ; l'action se
/// déclenche quand le pouce dépasse 85 % de la piste.
class _GlisserPourConfirmer extends StatefulWidget {
  const _GlisserPourConfirmer({
    super.key,
    required this.texte,
    required this.couleur,
    required this.icone,
    required this.enChargement,
    required this.onConfirme,
  });

  final String texte;
  final Color couleur;
  final IconData icone;
  final bool enChargement;
  final Future<void> Function() onConfirme;

  @override
  State<_GlisserPourConfirmer> createState() => _GlisserPourConfirmerState();
}

class _GlisserPourConfirmerState extends State<_GlisserPourConfirmer>
    with SingleTickerProviderStateMixin {
  static const double _taillePouce = 56;
  double _position = 0; // 0..1
  late final AnimationController _retour = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  )..addListener(() => setState(() => _position = _depart * (1 - _retour.value)));
  double _depart = 0;

  @override
  void didUpdateWidget(covariant _GlisserPourConfirmer old) {
    super.didUpdateWidget(old);
    // Fin du traitement sans changement d'étape (erreur, photo annulée) :
    // le pouce revient au début.
    if (old.enChargement && !widget.enChargement && _position > 0) _revenir();
  }

  @override
  void dispose() {
    _retour.dispose();
    super.dispose();
  }

  void _revenir() {
    _depart = _position;
    _retour.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final largeurPiste = contraintes.maxWidth;
        final course = largeurPiste - _taillePouce - 8;
        return Semantics(
          button: true,
          label: widget.texte,
          child: GestureDetector(
            onTap: widget.enChargement
                ? null
                : () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Fais glisser le bouton vers la droite pour confirmer.'),
                      duration: Duration(seconds: 2),
                    )),
            child: Container(
              height: _taillePouce + 8,
              decoration: BoxDecoration(
                color: widget.couleur.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Remplissage derrière le pouce
                  Container(
                    width: _taillePouce + 8 + course * _position,
                    decoration: BoxDecoration(
                      color: widget.couleur.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(40),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(left: _taillePouce),
                      child: Opacity(
                        opacity: (1 - _position * 1.5).clamp(0.0, 1.0),
                        child: Text(
                          widget.enChargement ? 'Envoi…' : widget.texte,
                          style: TextStyle(
                            color: widget.couleur,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 4 + course * _position,
                    child: GestureDetector(
                      onHorizontalDragUpdate: widget.enChargement
                          ? null
                          : (d) {
                              _retour.stop();
                              setState(() {
                                _position = (_position + d.delta.dx / course).clamp(0.0, 1.0);
                              });
                            },
                      onHorizontalDragEnd: widget.enChargement
                          ? null
                          : (_) async {
                              if (_position >= 0.85) {
                                setState(() => _position = 1);
                                HapticFeedback.heavyImpact();
                                await widget.onConfirme();
                                // Si l'écran reste sur la même étape (annulation
                                // de la photo…), didUpdateWidget ramène le pouce ;
                                // sinon la clé change et un nouveau pouce apparaît.
                                if (mounted && !widget.enChargement && _position > 0) _revenir();
                              } else {
                                _revenir();
                              }
                            },
                      child: Container(
                        width: _taillePouce,
                        height: _taillePouce,
                        decoration: BoxDecoration(
                          color: widget.couleur,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: widget.couleur.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3)),
                          ],
                        ),
                        child: widget.enChargement
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Icon(widget.icone, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Plein écran vert « Colis livré » avec une coche qui rebondit.
class _EcranSucces extends StatelessWidget {
  const _EcranSucces();

  @override
  Widget build(BuildContext context) {
    final reduit = MediaQuery.disableAnimationsOf(context);
    return Container(
      color: Colors.green.shade600,
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduit ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: Curves.elasticOut,
        builder: (context, v, child) => Transform.scale(scale: v, child: child),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: Colors.white,
              child: Icon(Icons.check_rounded, size: 64, color: Colors.green),
            ),
            SizedBox(height: 20),
            Text(
              'Colis livré',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text('Merci, beau travail', style: TextStyle(color: Colors.white70, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
