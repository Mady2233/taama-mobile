// DESIGN_V4
//
// Envoi d'un colis (côté client) : formulaire.
//
// Inchangé : prix calculé UNIQUEMENT par le serveur (estimerCourier), jamais
// de prix inventé ; contrôle prix_annonce / PrixCourierChangeException avec
// confirmation explicite du nouveau prix ; creerCourier avec les mêmes
// champs.
//
// Nouveau :
// - choix des points façon VTC (EcranSelectionPointCourier) : adresse
//   lisible + repère, au lieu de coordonnées brutes envoyées au livreur ;
// - frise Collecte → Livraison, aperçu carte cadré sur les deux points ;
// - catégories en tuiles avec icônes (plus d'emojis) ;
// - numéro du destinataire validé (format malien, 8 chiffres) ;
// - longueurs max alignées sur le modèle (description 200) ;
// - barre du bas fixe : prix qui défile + bouton Commander ;
// - après commande : écran de suivi dédié (EcranSuiviCourier).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../carte/fond_carte.dart';
import '../services/api_service.dart';
import '../services/courses_en_cours.dart';
import '../theme/taama_theme.dart';
import '../utils/format.dart';
import '../widgets/couche_carte_taama.dart';
import 'courier_selection_point.dart';
import 'courier_suivi_screen.dart';

const int _longueurMaxDescription = 200;

class EcranCourier extends StatefulWidget {
  const EcranCourier({super.key});

  @override
  State<EcranCourier> createState() => _EcranCourierState();
}

class _EcranCourierState extends State<EcranCourier> {
  final _descriptionController = TextEditingController();
  final _telephoneDestinataireController = TextEditingController();
  PointCourier? _collecte;
  PointCourier? _livraison;
  String _categorie = 'colis';

  // Prix calculé par le SERVEUR (jamais par l'app) dès que les deux points
  // sont choisis. Null tant qu'il n'est pas connu : pas de prix inventé.
  int? _prix;
  double? _distanceKm;
  bool _estimationEnCours = false;
  String? _erreurEstimation;
  bool _enChargement = false;

  static const _categories = [
    ('colis', Icons.inventory_2_rounded, 'Colis'),
    ('repas', Icons.restaurant_rounded, 'Repas'),
    ('document', Icons.description_rounded, 'Document'),
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    _telephoneDestinataireController.dispose();
    super.dispose();
  }

  // ─── Points ───

  Future<void> _choisirPoint({required bool estCollecte}) async {
    final point = await Navigator.push<PointCourier>(
      context,
      MaterialPageRoute(
        builder: (_) => EcranSelectionPointCourier(
          estCollecte: estCollecte,
          pointInitial: estCollecte ? _collecte : _livraison,
        ),
      ),
    );
    if (point == null || !mounted) return;
    setState(() {
      if (estCollecte) {
        _collecte = point;
      } else {
        _livraison = point;
      }
      // Un point a changé : l'ancien prix ne vaut plus rien.
      _prix = null;
      _distanceKm = null;
      _erreurEstimation = null;
    });
    _estimer();
  }

  Future<void> _estimer() async {
    final c = _collecte, l = _livraison;
    if (c == null || l == null) return;
    setState(() {
      _estimationEnCours = true;
      _erreurEstimation = null;
    });
    try {
      final resultat = await ApiService.estimerCourier(
        latCollecte: c.position.latitude,
        lngCollecte: c.position.longitude,
        latLivraison: l.position.latitude,
        lngLivraison: l.position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _prix = (resultat['prix'] as num).toInt();
        _distanceKm = (resultat['distance_km'] as num).toDouble();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreurEstimation = 'Impossible de calculer le prix. Vérifie ta connexion.');
    } finally {
      if (mounted) setState(() => _estimationEnCours = false);
    }
  }

  // ─── Validation ───

  /// Numéro malien : 8 chiffres, préfixe +223 / 00223 accepté et retiré
  /// (le backend stocke le format local). Vide = facultatif.
  String? _telephoneNormalise() {
    var t = _telephoneDestinataireController.text.replaceAll(RegExp(r'[\s.\-]'), '');
    if (t.isEmpty) return '';
    if (t.startsWith('+223')) {
      t = t.substring(4);
    } else if (t.startsWith('00223')) {
      t = t.substring(5);
    }
    return RegExp(r'^\d{8}$').hasMatch(t) ? t : null;
  }

  Future<bool> _confirmerNouveauPrix(int nouveauPrix) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Le prix a changé'),
        content: Text('Le prix de cette livraison est maintenant de '
            '${formaterFcfa(nouveauPrix)}. Commander à ce prix ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Commander à ${formaterFcfa(nouveauPrix)}'),
          ),
        ],
      ),
    );
    return confirme ?? false;
  }

  void _message(String texte) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texte)));
  }

  // ─── Commande ───

  Future<void> _commander() async {
    final c = _collecte, l = _livraison, prix = _prix;
    if (c == null || l == null) {
      _message('Choisis le point de collecte et le point de livraison.');
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _message('Décris le colis en quelques mots.');
      return;
    }
    final telephone = _telephoneNormalise();
    if (telephone == null) {
      _message('Numéro du destinataire invalide : 8 chiffres (ex. 70 00 00 00).');
      return;
    }
    if (prix == null) return;

    setState(() => _enChargement = true);
    try {
      final resultat = await ApiService.creerCourier(
        adresseCollecte: c.adresse,
        adresseLivraison: l.adresse,
        descriptionColis: _descriptionController.text.trim(),
        categorie: _categorie,
        telephoneDestinataire: telephone,
        prixAnnonce: prix,
        latCollecte: c.position.latitude,
        lngCollecte: c.position.longitude,
        latLivraison: l.position.latitude,
        lngLivraison: l.position.longitude,
      );
      // Livraison en cours pour la déconnexion, même si l'écran est déjà fermé.
      final id = resultat['id'];
      if (id is int) await CoursesEnCours.enregistrerLivraison(id);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EcranSuiviCourier(
            commande: resultat,
            pointCollecte: c.position,
            pointLivraison: l.position,
            adresseCollecte: c.adresse,
            adresseLivraison: l.adresse,
          ),
        ),
      );
    } on PrixCourierChangeException catch (e) {
      // Rien n'a été commandé : on affiche le nouveau prix et on ne
      // recommande qu'avec l'accord explicite du client.
      if (!mounted) return;
      setState(() {
        _prix = e.nouveauPrix;
        if (e.distanceKm != null) _distanceKm = e.distanceKm;
        _enChargement = false;
      });
      if (await _confirmerNouveauPrix(e.nouveauPrix) && mounted) {
        await _commander();
      }
      return;
    } catch (e) {
      if (!mounted) return;
      _message(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
  }

  // ─── Construction ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TaamaColors.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _enTete()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverList.list(
              children: [
                _carteTrajet(),
                if (_collecte != null && _livraison != null) ...[
                  const SizedBox(height: 12),
                  _ApercuTrajet(
                    collecte: _collecte!.position,
                    livraison: _livraison!.position,
                  ),
                ],
                const SizedBox(height: 16),
                _titreSection('Que veux-tu envoyer ?'),
                const SizedBox(height: 10),
                _choixCategorie(),
                const SizedBox(height: 14),
                _champ(
                  controleur: _descriptionController,
                  icone: Icons.notes_rounded,
                  indication: 'Ex. 2 pagnes, un dossier, un plat…',
                  longueurMax: _longueurMaxDescription,
                  lignes: 2,
                ),
                const SizedBox(height: 16),
                _titreSection('Destinataire (facultatif)'),
                const SizedBox(height: 10),
                _champ(
                  controleur: _telephoneDestinataireController,
                  icone: Icons.phone_rounded,
                  indication: 'Numéro : 70 00 00 00',
                  clavier: TextInputType.phone,
                  formateurs: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  longueurMax: 16,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'S’il a un compte Taama, il pourra suivre le colis et payer lui-même.',
                    style: TaamaText.muted.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _barreCommande(),
    );
  }

  Widget _enTete() {
    final haut = MediaQuery.paddingOf(context).top;
    return Container(
      padding: EdgeInsets.fromLTRB(8, haut + 4, 20, 24),
      decoration: const BoxDecoration(
        color: TaamaColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(TaamaRadius.xl + 8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: 'Retour',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Envoyer un colis',
                        style: TaamaText.title.copyWith(color: Colors.white, fontSize: 26),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Un livreur le récupère et le livre partout à Bamako.',
                        style: TaamaText.body.copyWith(color: TaamaColors.onNavyMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: TaamaColors.primary,
                    borderRadius: BorderRadius.circular(TaamaRadius.lg),
                  ),
                  child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 32),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _titreSection(String texte) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(texte, style: TaamaText.body.copyWith(fontWeight: FontWeight.w800, fontSize: 15)),
      );

  Widget _carteTrajet() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        boxShadow: TaamaShadows.card,
      ),
      child: Column(
        children: [
          _LignePoint(
            titre: 'Collecte',
            indication: 'Où récupérer le colis ?',
            adresse: _collecte?.adresse,
            couleur: TaamaColors.navy,
            icone: Icons.inventory_2_rounded,
            avecLigne: true,
            onTap: () => _choisirPoint(estCollecte: true),
          ),
          _LignePoint(
            titre: 'Livraison',
            indication: 'Où livrer le colis ?',
            adresse: _livraison?.adresse,
            couleur: TaamaColors.primary,
            icone: Icons.flag_rounded,
            avecLigne: false,
            onTap: () => _choisirPoint(estCollecte: false),
          ),
        ],
      ),
    );
  }

  Widget _choixCategorie() {
    return Row(
      children: [
        for (final (valeur, icone, libelle) in _categories)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: valeur == _categories.last.$1 ? 0 : 10),
              child: _TuileCategorie(
                icone: icone,
                libelle: libelle,
                choisie: _categorie == valeur,
                onTap: () => setState(() => _categorie = valeur),
              ),
            ),
          ),
      ],
    );
  }

  Widget _champ({
    required TextEditingController controleur,
    required IconData icone,
    required String indication,
    int? longueurMax,
    int lignes = 1,
    TextInputType? clavier,
    List<TextInputFormatter>? formateurs,
  }) {
    return TextField(
      controller: controleur,
      maxLength: longueurMax,
      maxLines: lignes,
      minLines: 1,
      keyboardType: clavier,
      inputFormatters: formateurs,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: indication,
        prefixIcon: Icon(icone),
        counterText: '',
        filled: true,
        fillColor: TaamaColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TaamaRadius.md),
          borderSide: const BorderSide(color: TaamaColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TaamaRadius.md),
          borderSide: const BorderSide(color: TaamaColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TaamaRadius.md),
          borderSide: const BorderSide(color: TaamaColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _barreCommande() {
    final pointsOk = _collecte != null && _livraison != null;
    Widget prix;
    if (!pointsOk) {
      prix = Text('Choisis les 2 points', key: const ValueKey('points'), style: TaamaText.muted);
    } else if (_estimationEnCours) {
      prix = Row(
        key: const ValueKey('calcul'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: TaamaColors.primary),
          ),
          const SizedBox(width: 8),
          Text('Calcul…', style: TaamaText.muted),
        ],
      );
    } else if (_erreurEstimation != null || _prix == null) {
      prix = TextButton.icon(
        key: const ValueKey('erreur'),
        onPressed: _estimer,
        icon: const Icon(Icons.refresh_rounded, color: TaamaColors.danger),
        label: const Text('Réessayer', style: TextStyle(color: TaamaColors.danger)),
      );
    } else {
      prix = Column(
        key: ValueKey(_prix),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(
              begin: MediaQuery.disableAnimationsOf(context) ? _prix!.toDouble() : 0,
              end: _prix!.toDouble(),
            ),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              formaterFcfa(v.round()),
              style: TaamaText.title.copyWith(fontSize: 22, color: TaamaColors.textPrimary),
            ),
          ),
          if (_distanceKm != null)
            Text('${_distanceKm!.toStringAsFixed(1)} km · prix fixé', style: TaamaText.muted.copyWith(fontSize: 12)),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        boxShadow: TaamaShadows.floating,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  layoutBuilder: (actuel, precedents) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...precedents, if (actuel != null) actuel],
                  ),
                  child: prix,
                ),
              ),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  // Désactivé tant que le serveur n'a pas donné de prix.
                  onPressed: (_enChargement || _prix == null) ? null : _commander,
                  icon: _enChargement
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Commander', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TaamaColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(150, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TaamaRadius.lg)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Widgets ───

class _LignePoint extends StatelessWidget {
  const _LignePoint({
    required this.titre,
    required this.indication,
    required this.adresse,
    required this.couleur,
    required this.icone,
    required this.avecLigne,
    required this.onTap,
  });

  final String titre;
  final String indication;
  final String? adresse;
  final Color couleur;
  final IconData icone;
  final bool avecLigne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final choisi = adresse != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TaamaRadius.md),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: choisi ? couleur : couleur.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icone, size: 18, color: choisi ? Colors.white : couleur),
                  ),
                  if (avecLigne)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.only(top: 4),
                        color: TaamaColors.border,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 10, bottom: avecLigne ? 14 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre.toUpperCase(),
                      style: TaamaText.muted.copyWith(fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      adresse ?? indication,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TaamaText.body.copyWith(
                        fontWeight: choisi ? FontWeight.w800 : FontWeight.w600,
                        color: choisi ? TaamaColors.textPrimary : TaamaColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Icon(
                choisi ? Icons.edit_rounded : Icons.chevron_right_rounded,
                color: TaamaColors.textSecondary,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TuileCategorie extends StatelessWidget {
  const _TuileCategorie({
    required this.icone,
    required this.libelle,
    required this.choisie,
    required this.onTap,
  });

  final IconData icone;
  final String libelle;
  final bool choisie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: choisie ? TaamaColors.primary : TaamaColors.surface,
          borderRadius: BorderRadius.circular(TaamaRadius.lg),
          border: Border.all(color: choisie ? TaamaColors.primary : TaamaColors.border),
          boxShadow: choisie ? TaamaShadows.floating : const [],
        ),
        child: Column(
          children: [
            AnimatedScale(
              scale: choisie ? 1.15 : 1,
              duration: const Duration(milliseconds: 220),
              child: Icon(icone, color: choisie ? Colors.white : TaamaColors.primary, size: 26),
            ),
            const SizedBox(height: 6),
            Text(
              libelle,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: choisie ? Colors.white : TaamaColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aperçu non interactif cadré sur les deux points.
class _ApercuTrajet extends StatelessWidget {
  const _ApercuTrajet({required this.collecte, required this.livraison});
  final LatLng collecte;
  final LatLng livraison;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(TaamaRadius.lg),
      child: SizedBox(
        height: 150,
        child: FlutterMap(
          key: ValueKey('$collecte$livraison'),
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints([collecte, livraison]),
              padding: const EdgeInsets.all(36),
              maxZoom: 16,
            ),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            const FondCarteTaama(apercu: true),
            const CoucheCarteTaama(),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: [collecte, livraison],
                  color: TaamaColors.primary,
                  strokeWidth: 3,
                  pattern: StrokePattern.dashed(segments: const [8, 6]),
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(point: collecte, width: 30, height: 30, child: const _Pastille(couleur: TaamaColors.navy, icone: Icons.inventory_2_rounded)),
                Marker(point: livraison, width: 30, height: 30, child: const _Pastille(couleur: TaamaColors.primary, icone: Icons.flag_rounded)),
              ],
            ),
            const AttributionCarteTaama(),
          ],
        ),
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
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Icon(icone, color: Colors.white, size: 15),
    );
  }
}
