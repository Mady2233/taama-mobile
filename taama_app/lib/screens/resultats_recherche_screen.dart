import 'dart:convert';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/app_config.dart';
import '../models/service_course.dart';
import '../services/api_service.dart';
import '../services/routing_service.dart';
import '../theme/taama_theme.dart';
import '../widgets/couche_carte_taama.dart';
import '../carte/fond_carte.dart';
import '../widgets/widget_choix_vehicule.dart';
import 'course/suivi_course_page.dart';
import 'recherche_screen.dart';

/// Écran de demande instantanée : la distance est calculée automatiquement
/// (GPS + géocodage Nominatim + Haversine), puis le passager choisit son
/// véhicule et l'app cherche un conducteur disponible.
///
/// Style v4 (TaamaColors / TaamaText) : carte en haut, feuille arrondie en
/// dessous, cohérent avec l'accueil et la recherche. La LOGIQUE est inchangée
/// — prix exclusivement serveur, gestion du devis expiré, code promo validé
/// côté serveur.
class EcranDemandeInstantanee extends StatefulWidget {
  final String destination;
  final String? typePreselectionne;

  const EcranDemandeInstantanee({
    super.key,
    required this.destination,
    this.typePreselectionne,
  });

  @override
  State<EcranDemandeInstantanee> createState() =>
      _EcranDemandeInstantaneeState();
}

class _EcranDemandeInstantaneeState
    extends State<EcranDemandeInstantanee> {
  bool _calcul = true;
  bool _enChargement = false;
  double? _distanceKm;
  String? _erreur;
  // Devis reçus du serveur (POST /trajets/estimer/) — plus aucun prix
  // calculé côté client : ce que cette liste contient est ce qui s'affiche,
  // point final. Null tant qu'aucune estimation n'a réussi ; jamais vide-
  // par-erreur silencieuse (voir _recalculerEstimation, _erreur distingue
  // "en cours"/"échoué" de "0 service dispo").
  List<ServiceCourse>? _services;
  // Position GPS du client au moment du calcul — transmise à la création de
  // la demande pour attribuer le chauffeur le plus proche.
  double? _departLat;
  double? _departLng;
  // Position GPS de la destination géocodée — déjà calculée juste en
  // dessous pour l'estimation de distance/prix, transmise en plus à la
  // création de la demande pour guider la 2e jambe de navigation du
  // conducteur (client à bord -> destination).
  double? _destinationLat;
  double? _destinationLng;

  // Planification
  bool _planifier = false;
  DateTime? _datePlanifiee;
  TimeOfDay? _heurePlanifiee;

  // Code promo — validé côté serveur avant confirmation (aperçu, ne
  // consomme aucun quota) ; la réduction réellement appliquée dépend du
  // véhicule choisi ensuite dans le bottom sheet et n'est recalculée
  // qu'à la création finale (voir _confirmer), toujours côté serveur.
  final TextEditingController _codePromoCtrl = TextEditingController();
  bool _verificationCodePromoEnCours = false;
  bool? _codePromoValide;
  int? _reductionCodePromo;
  String? _erreurCodePromo;

  // Arrêts intermédiaires — MVP volontairement simple : quand des arrêts
  // sont présents, on force le flux statique (Voiture/Moto, jamais le
  // catalogue TypeService dynamique) et on n'utilise plus le détail de prix
  // backend (calculé uniquement pour un trajet à 2 points), pour ne jamais
  // afficher un prix qui sous-estimerait celui réellement facturé à la
  // création (voir _recalculerEstimation et _confirmer).
  static const int _maxArrets = 3;
  final List<Map<String, dynamic>> _arrets = [];
  bool _recalculEnCours = false;

  @override
  void initState() {
    super.initState();
    _calculerDistanceAuto();
  }

  /// « À partir de » (voir prixAPartirDe) : affiché avec ou sans chauffeur,
  /// sert aussi de référence à
  /// l'aperçu de réduction du code promo (la réduction réelle dépend du
  /// service choisi ensuite dans le sheet, revalidée à la création).
  int? get _prixReference => prixAPartirDe(
        _services ?? const [],
        typePreselectionne: widget.typePreselectionne,
      );

  /// Purement informatif : commander dépend de _peutCommander.
  bool get _chauffeurDisponible => chauffeurDisponible(
        _services ?? const [],
        typePreselectionne: widget.typePreselectionne,
      );

  bool get _peutCommander => peutCommander(
        _services ?? const [],
        typePreselectionne: widget.typePreselectionne,
      );

  Future<void> _verifierCodePromo() async {
    final code = _codePromoCtrl.text.trim();
    if (code.isEmpty) return;
    final prixReference = _prixReference;
    if (prixReference == null) return;

    setState(() {
      _verificationCodePromoEnCours = true;
      _codePromoValide = null;
      _erreurCodePromo = null;
    });
    try {
      final resultat = await ApiService.validerCodePromo(
        code: code,
        prix: prixReference,
      );
      if (!mounted) return;
      setState(() {
        _codePromoValide = true;
        _reductionCodePromo = resultat['reduction'] as int?;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _codePromoValide = false;
        _erreurCodePromo = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _verificationCodePromoEnCours = false);
    }
  }

  Future<void> _calculerDistanceAuto() async {
    setState(() { _calcul = true; _erreur = null; });
    try {
      // 1. Position GPS du client
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );

      // 2. Géocode la destination (Nominatim OSM - gratuit)
      final destGeocodee = await _geocoder(widget.destination);
      if (!mounted) return;

      setState(() {
        _departLat = position.latitude;
        _departLng = position.longitude;
        // Ne renseigne _destinationLat/Lng QUE si le géocodage a réussi —
        // ne doivent JAMAIS pointer vers le centre de Bamako par défaut, ça
        // guiderait le conducteur au mauvais endroit (voir _recalculerEstimation,
        // qui utilise ce défaut uniquement pour l'ESTIMATION locale, jamais
        // transmis tel quel au backend).
        if (destGeocodee != null) {
          _destinationLat = destGeocodee.latitude;
          _destinationLng = destGeocodee.longitude;
        }
      });

      await _recalculerEstimation();
    } catch (e) {
      // Jamais de distance/prix fabriqués : mieux vaut un état d'erreur
      // explicite qu'une estimation qui ne repose sur rien (le client
      // pourrait confirmer une course sur un prix totalement faux).
      if (!mounted) return;
      setState(() {
        _distanceKm = null;
        _erreur = 'Impossible de vous localiser — réessayez';
      });
    } finally {
      // Toujours exécuté : le spinner "Calcul de la distance..." ne doit
      // jamais rester affiché indéfiniment, quel que soit le chemin pris.
      if (mounted) setState(() => _calcul = false);
    }
  }

  /// Géocode un texte d'adresse via Nominatim (OSM, gratuit) — `null` si
  /// introuvable ou en cas d'erreur réseau, jamais d'exception.
  Future<LatLng?> _geocoder(String texte) async {
    try {
      final q = Uri.encodeComponent('$texte, Bamako, Mali');
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=1');
      final reponse = await http.get(url, headers: {
        'User-Agent': AppConfig.userAgentHttp,
      }).timeout(const Duration(seconds: 10));
      if (reponse.statusCode == 200) {
        final res = jsonDecode(reponse.body) as List;
        if (res.isNotEmpty) {
          return LatLng(
            double.parse(res[0]['lat'].toString()),
            double.parse(res[0]['lon'].toString()),
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// Recalcule les devis pour le trajet complet (départ -> arrêts ->
  /// destination) — appelée après le calcul initial et à chaque ajout/retrait
  /// d'arrêt. Prix et distance viennent EXCLUSIVEMENT du serveur
  /// (POST /trajets/estimer/, voir ApiService.estimerCourse) : aucune
  /// formule locale, aucun repli sur une estimation approximative — un
  /// échec réseau/HTTP est un état d'erreur explicite (_erreur), jamais un
  /// prix fabriqué sur lequel le client pourrait confirmer une course.
  Future<void> _recalculerEstimation() async {
    if (_departLat == null || _departLng == null) return;
    if (_destinationLat == null || _destinationLng == null) {
      if (!mounted) return;
      setState(() {
        _services = null;
        _distanceKm = null;
        _erreur = 'Destination introuvable — réessayez';
      });
      return;
    }

    try {
      final services = await ApiService.estimerCourse(
        departLat: _departLat!, departLng: _departLng!,
        arriveeLat: _destinationLat!, arriveeLng: _destinationLng!,
        arrets: _arrets,
      );
      if (!mounted) return;
      setState(() {
        _services = services;
        // Même distance sur chaque entrée (un seul trajet estimé) — voir
        // le commentaire de estimer_course, backend.
        _distanceKm = services.isNotEmpty ? services.first.distanceKm : null;
        _erreur = null;
      });
    } on EstimationIndisponibleException catch (e) {
      if (!mounted) return;
      setState(() {
        _services = null;
        _distanceKm = null;
        _erreur = 'Impossible de calculer le prix — réessayez';
      });
      debugPrint('[Resultats] estimerCourse KO : $e');
    }
  }

  Future<void> _ajouterArret() async {
    if (_arrets.length >= _maxArrets) return;
    final resultat = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const EcranRecherche()),
    );
    if (resultat == null || resultat.trim().isEmpty || !mounted) return;

    setState(() => _recalculEnCours = true);
    try {
      final point = await _geocoder(resultat);
      if (!mounted) return;
      if (point == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Adresse introuvable : $resultat')),
        );
        return;
      }

      setState(() {
        _arrets.add({
          'adresse': resultat,
          'latitude': point.latitude,
          'longitude': point.longitude,
        });
      });
      await _recalculerEstimation();
    } finally {
      if (mounted) setState(() => _recalculEnCours = false);
    }
  }

  Future<void> _supprimerArret(int index) async {
    setState(() => _arrets.removeAt(index));
    await _recalculerEstimation();
  }

  Future<void> _confirmer() async {
    final services = _services;
    if (_distanceKm == null || services == null || services.isEmpty) {
      // Ne devrait pas arriver (bouton désactivé tant que _services est
      // null/vide), mais jamais un no-op silencieux si ça se produit quand même.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Prix non disponible, réessayez dans un instant.')),
      );
      return;
    }

    final choix = await afficherChoixVehicule(
      context,
      destination: widget.destination,
      distanceKm: _distanceKm!,
      typePreselectionne: widget.typePreselectionne,
      services: services,
    );
    if (choix == null || !mounted) return;

    // Planifier reste réservé à un service avec un chauffeur proche : les
    // courses planifiées ne sont pas encore activées automatiquement.
    if (_planifier && choix['disponible'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aucun chauffeur proche pour ce service : impossible de planifier pour le moment.')));
      return;
    }

    DateTime? dateHeurePlanifiee;
    if (_planifier && _datePlanifiee != null && _heurePlanifiee != null) {
      dateHeurePlanifiee = DateTime(
        _datePlanifiee!.year, _datePlanifiee!.month, _datePlanifiee!.day,
        _heurePlanifiee!.hour, _heurePlanifiee!.minute,
      );
      if (dateHeurePlanifiee.isBefore(
          DateTime.now().add(const Duration(minutes: 30)))) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Planifie au moins 30 min à l\'avance')));
        return;
      }
    }

    // Envoyé tel quel si non-vide, même si _verifierCodePromo n'a jamais été
    // appuyé — le serveur re-valide intégralement et rejette toute la
    // demande si le code est invalide (jamais une réduction silencieusement
    // ignorée, voir creer_demande_instantanee côté backend).
    final codePromoSaisi = _codePromoCtrl.text.trim();
    final codePromo = codePromoSaisi.isEmpty ? null : codePromoSaisi;

    await _soumettre(
      devisId: choix['devis_id'] as int,
      typeServiceId: choix['type_service'] as int,
      prixAffiche: choix['prix_estime'] as int?,
      dateHeurePlanifiee: dateHeurePlanifiee,
      codePromo: codePromo,
    );
  }

  /// Poste la demande avec ce devis. Si le devis a expiré ENTRE le choix du
  /// véhicule et cette confirmation, le serveur en renvoie un nouveau (même
  /// service/trajet, prix recalculé maintenant) : même prix -> on continue
  /// avec lui, sans rien redemander (rien n'a changé pour le client) ; prix
  /// différent -> on l'affiche et on exige une confirmation explicite avant
  /// de reposter. Jamais de commande envoyée sur un prix non validé.
  /// [dejaRelance] borne à UNE seule reconfirmation automatique/silencieuse,
  /// pour ne jamais boucler indéfiniment sur des devis qui expirent en
  /// continu (réseau très lent, etc.).
  Future<void> _soumettre({
    required int devisId,
    required int typeServiceId,
    required int? prixAffiche,
    required DateTime? dateHeurePlanifiee,
    required String? codePromo,
    bool dejaRelance = false,
  }) async {
    setState(() => _enChargement = true);
    try {
      final demande = await ApiService.creerDemandeInstantanee(
        destination: widget.destination,
        devisId: devisId,
        typeServiceId: typeServiceId,
        dateHeurePlanifiee: dateHeurePlanifiee,
        codePromo: codePromo,
      );
      if (!mounted) return;

      if (dateHeurePlanifiee != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Course planifiée avec succès !')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SuiviCoursePage(
              demandeId: demande['id'] as int,
              destination: widget.destination,
              // demande['type_transport'] (renvoyé par le serveur, dérivé
              // côté backend même pour le chemin type_service) — PAS
              // choix['type'], absent en mode dynamique et qui ferait
              // planter ce cast.
              typeTransport: demande['type_transport'] as String,
            ),
          ),
        );
      }
    } on DevisExpireException catch (e) {
      if (!mounted) return;
      if (dejaRelance) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Le prix a expiré à nouveau — relance la recherche.')));
        await _recalculerEstimation();
        return;
      }
      if (prixAffiche != null && e.nouveauPrix == prixAffiche) {
        // Même prix : le devis a juste dépassé sa fenêtre de 5 min entre le
        // choix et la confirmation, rien n'a changé pour le client.
        await _soumettre(
          devisId: e.nouveauDevisId, typeServiceId: typeServiceId,
          prixAffiche: e.nouveauPrix, dateHeurePlanifiee: dateHeurePlanifiee,
          codePromo: codePromo, dejaRelance: true,
        );
        return;
      }
      // Prix différent : jamais de commande sur un prix non validé.
      final accepte = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Le prix a changé'),
          content: Text(
            prixAffiche != null
                ? 'Le prix est maintenant de ${e.nouveauPrix} FCFA (au lieu de $prixAffiche FCFA). Confirmer à ce nouveau prix ?'
                : 'Le prix est maintenant de ${e.nouveauPrix} FCFA. Confirmer ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      );
      if (accepte == true && mounted) {
        await _soumettre(
          devisId: e.nouveauDevisId, typeServiceId: typeServiceId,
          prixAffiche: e.nouveauPrix, dateHeurePlanifiee: dateHeurePlanifiee,
          codePromo: codePromo, dejaRelance: true,
        );
      } else if (mounted) {
        await _recalculerEstimation();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', ''))));
      // Le devis n'est peut-être plus utilisable (purgé, déjà consommé) :
      // jamais de client bloqué sur un devis mort.
      await _recalculerEstimation();
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
  }

  @override
  void dispose() {
    _codePromoCtrl.dispose();
    super.dispose();
  }

  // ─── Construction (v4) ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TaamaColors.background,
      body: LayoutBuilder(
        builder: (context, contraintes) {
          final hauteurCarte = contraintes.maxHeight * 0.34;
          return Stack(
            children: [
              // Carte : s'arrête au bord de la feuille (le fond neutre remplit
              // les coins arrondis, pas d'étiquette qui dépasse).
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: hauteurCarte,
                child: _CarteApercuItineraire(
                  depart: (_departLat != null && _departLng != null)
                      ? LatLng(_departLat!, _departLng!)
                      : null,
                  destination: (_destinationLat != null && _destinationLng != null)
                      ? LatLng(_destinationLat!, _destinationLng!)
                      : null,
                  arrets: _arrets
                      .map((a) =>
                          LatLng(a['latitude'] as double, a['longitude'] as double))
                      .toList(),
                  enCalcul: _calcul,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _BoutonRetourRond(onTap: () => Navigator.pop(context)),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: hauteurCarte,
                bottom: 0,
                child: _feuille(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _feuille() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TaamaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
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
            _carteDestination(),
            const SizedBox(height: 12),
            _carteArrets(),
            const SizedBox(height: 12),
            _carteDistancePrix(),
            const SizedBox(height: 12),
            _cartePlanification(),
            const SizedBox(height: 12),
            _carteCodePromo(),
            const SizedBox(height: 20),
            _boutonConfirmer(),
          ],
        ),
      ),
    );
  }

  Widget _carteDestination() {
    return _Carte(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: TaamaColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.place_rounded, color: TaamaColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Destination', style: TaamaText.muted.copyWith(fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  widget.destination,
                  style: TaamaText.body.copyWith(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteArrets() {
    return _Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _arrets.length; i++) ...[
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: TaamaColors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('${i + 1}',
                        style: TaamaText.body.copyWith(
                            color: TaamaColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _arrets[i]['adresse']?.toString() ?? '',
                    style: TaamaText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer cet arrêt',
                  onPressed: _recalculEnCours ? null : () => _supprimerArret(i),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: TaamaColors.textSecondary,
                ),
              ],
            ),
            if (i < _arrets.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(width: 32, child: Divider()),
              ),
          ],
          if (_arrets.isNotEmpty) const SizedBox(height: 12),
          if (_arrets.length < _maxArrets)
            InkWell(
              borderRadius: BorderRadius.circular(TaamaRadius.sm),
              onTap: _recalculEnCours ? null : _ajouterArret,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: TaamaColors.primary.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: _recalculEnCours
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: TaamaColors.primary),
                            )
                          : const Icon(Icons.add_rounded,
                              color: TaamaColors.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Text('Ajouter un arrêt',
                        style: TaamaText.body.copyWith(
                            color: TaamaColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _carteDistancePrix() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TaamaColors.navy,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
      ),
      child: _calcul
          ? const Column(
              children: [
                CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                SizedBox(height: 10),
                Text('Calcul de la distance…',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            )
          : _distanceKm == null
              // Jamais de distance/prix fabriqués (voir catch de
              // _calculerDistanceAuto) : état d'erreur explicite + bouton.
              ? Column(
                  children: [
                    const Icon(Icons.location_off_rounded, color: Colors.white70, size: 22),
                    const SizedBox(height: 6),
                    Text(
                      _erreur ?? 'Impossible de vous localiser — réessayez',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _calculerDistanceAuto,
                      icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                      label: const Text('Réessayer', style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white70),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatPrix(
                          icone: Icons.straighten_rounded,
                          label: 'Distance',
                          valeur: '${_distanceKm!.toStringAsFixed(1)} km',
                        ),
                        if (_prixReference != null)
                          _StatPrix(
                            icone: Icons.payments_outlined,
                            label: 'À partir de',
                            valeur: '$_prixReference FCFA',
                            accent: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 10),
                    // Disponibilité : ligne distincte du prix. Pas de nombre
                    // de chauffeurs : une berline climatisée compte à la fois
                    // dans Berline et Confort, le total serait faux.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _chauffeurDisponible
                              ? Icons.check_circle_rounded
                              : Icons.person_search_rounded,
                          size: 16,
                          color: _chauffeurDisponible ? TaamaColors.accentMint : Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _chauffeurDisponible
                                ? 'Chauffeurs à proximité'
                                : 'Aucun chauffeur à proximité · nous en cherchons un pour vous',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    // Prix figé par le devis, avec ou sans chauffeur.
                    if (_peutCommander) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 14, color: Colors.white70),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Prix fixé à l’avance · payé en espèces au chauffeur',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _calculerDistanceAuto,
                      icon: const Icon(Icons.refresh_rounded, size: 15, color: Colors.white70),
                      label: Text(_chauffeurDisponible ? 'Recalculer' : 'Réessayer',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                    ),
                  ],
                ),
    );
  }

  Widget _cartePlanification() {
    return _Carte(
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, color: TaamaColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Planifier à l’avance',
                    style: TaamaText.body.copyWith(fontWeight: FontWeight.w800)),
              ),
              Switch(
                value: _planifier,
                onChanged: (v) => setState(() => _planifier = v),
                activeThumbColor: TaamaColors.primary,
              ),
            ],
          ),
          if (_planifier) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(hours: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (d != null) setState(() => _datePlanifiee = d);
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 16),
                    label: Text(_datePlanifiee == null
                        ? 'Date'
                        : '${_datePlanifiee!.day}/${_datePlanifiee!.month}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TaamaColors.primary,
                      side: const BorderSide(color: TaamaColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final h = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (h != null) setState(() => _heurePlanifiee = h);
                    },
                    icon: const Icon(Icons.access_time_rounded, size: 16),
                    label: Text(_heurePlanifiee == null
                        ? 'Heure'
                        : _heurePlanifiee!.format(context)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: TaamaColors.primary,
                      side: const BorderSide(color: TaamaColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _carteCodePromo() {
    return _Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_outlined, color: TaamaColors.primary, size: 20),
              const SizedBox(width: 10),
              Text('Code promo', style: TaamaText.body.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codePromoCtrl,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) {
                    // Un changement invalide l'aperçu précédent : évite
                    // d'afficher une réduction qui ne correspond plus au texte.
                    if (_codePromoValide != null) {
                      setState(() {
                        _codePromoValide = null;
                        _erreurCodePromo = null;
                      });
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Ex : BIENVENUE',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TaamaRadius.md),
                      borderSide: const BorderSide(color: TaamaColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TaamaRadius.md),
                      borderSide: const BorderSide(color: TaamaColors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _verificationCodePromoEnCours ? null : _verifierCodePromo,
                style: OutlinedButton.styleFrom(
                  foregroundColor: TaamaColors.primary,
                  side: const BorderSide(color: TaamaColors.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(TaamaRadius.md)),
                ),
                child: _verificationCodePromoEnCours
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: TaamaColors.primary),
                      )
                    : const Text('Vérifier'),
              ),
            ],
          ),
          if (_codePromoValide == true) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: TaamaColors.success, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Code valide — réduction estimée de $_reductionCodePromo FCFA',
                    style: const TextStyle(
                        color: TaamaColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ] else if (_codePromoValide == false) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: TaamaColors.danger, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _erreurCodePromo ?? 'Code invalide',
                    style: const TextStyle(
                        color: TaamaColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _boutonConfirmer() {
    final actif = !(_calcul || _enChargement || _distanceKm == null || !_peutCommander ||
        (_planifier && !_chauffeurDisponible));
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: actif ? _confirmer : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: TaamaColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: TaamaColors.primary.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TaamaRadius.lg)),
          elevation: 3,
          shadowColor: TaamaColors.primary.withValues(alpha: 0.4),
        ),
        child: _enChargement
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_planifier ? Icons.event_available_rounded : Icons.local_taxi_rounded,
                      size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _planifier ? 'Planifier la course' : 'Choisir mon véhicule',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Carte blanche standard de cet écran (fond, coins, ombre douce).
class _Carte extends StatelessWidget {
  const _Carte({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        boxShadow: TaamaShadows.card,
      ),
      child: child,
    );
  }
}

class _BoutonRetourRond extends StatelessWidget {
  const _BoutonRetourRond({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: TaamaColors.surface,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: TaamaColors.textPrimary.withValues(alpha: 0.25),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 46,
            height: 46,
            child: Icon(Icons.arrow_back_rounded, color: TaamaColors.textPrimary, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Aperçu carte de l'itinéraire départ → destination : affiche les deux
/// marqueurs et le tracé réel (OSRM via [RoutingService]) une fois les deux
/// points connus, avec repli sur une ligne droite si OSRM est indisponible
/// (jamais de carte sans tracé — même logique fail-soft que le backend).
class _CarteApercuItineraire extends StatefulWidget {
  final LatLng? depart;
  final LatLng? destination;
  final List<LatLng> arrets;
  final bool enCalcul;

  const _CarteApercuItineraire({
    required this.depart,
    required this.destination,
    required this.arrets,
    required this.enCalcul,
  });

  @override
  State<_CarteApercuItineraire> createState() =>
      _CarteApercuItineraireState();
}

class _CarteApercuItineraireState extends State<_CarteApercuItineraire> {
  static const LatLng _centreParDefaut = LatLng(12.6392, -8.0029);

  final MapController _mapController = MapController();
  List<LatLng>? _trace;
  bool _chargementTrace = false;
  List<LatLng>? _pointsRequete;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _chargerSiNecessaire());
  }

  @override
  void didUpdateWidget(covariant _CarteApercuItineraire oldWidget) {
    super.didUpdateWidget(oldWidget);
    _chargerSiNecessaire();
  }

  void _chargerSiNecessaire() {
    final depart = widget.depart;
    final destination = widget.destination;
    if (depart == null || destination == null) return;
    final points = [depart, ...widget.arrets, destination];
    if (listEquals(points, _pointsRequete)) return;

    _pointsRequete = points;
    _ajusterCamera(points);
    _chargerTrace(points);
  }

  void _ajusterCamera(List<LatLng> points) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.fromLTRB(40, 60, 40, 30),
          maxZoom: 16,
        ),
      );
    });
  }

  Future<void> _chargerTrace(List<LatLng> points) async {
    setState(() => _chargementTrace = true);
    final trace = await RoutingService.recupererItineraireMulti(points);
    if (!mounted) return;
    setState(() {
      // Repli ligne droite (segment par segment) si OSRM indisponible —
      // jamais de carte sans tracé.
      _trace = trace ?? points;
      _chargementTrace = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final depart = widget.depart;
    final destination = widget.destination;
    final pointsPrets = depart != null && destination != null;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: depart ?? _centreParDefaut,
            initialZoom: 13.0,
            // Plein nord, comme l'accueil (tuiles raster).
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            const FondCarteTaama(),
            const CoucheCarteTaama(),
            if (_trace != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _trace!,
                    strokeWidth: 4,
                    color: TaamaColors.primary,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (depart != null)
                  Marker(
                    point: depart,
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    child: Container(
                      decoration: BoxDecoration(
                        color: TaamaColors.navy,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(color: TaamaColors.ombreMarqueur, blurRadius: 6),
                        ],
                      ),
                      child: const Icon(Icons.trip_origin, color: Colors.white, size: 14),
                    ),
                  ),
                if (destination != null)
                  Marker(
                    point: destination,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on, color: TaamaColors.primary, size: 40),
                  ),
                for (var i = 0; i < widget.arrets.length; i++)
                  Marker(
                    point: widget.arrets[i],
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    child: Container(
                      decoration: BoxDecoration(
                        color: TaamaColors.star,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: TaamaColors.ombreMarqueur, blurRadius: 4),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const AttributionCarteTaama(),
          ],
        ),
        // Overlay de chargement uniquement pendant un calcul en cours (GPS
        // ou tracé OSRM) — si le calcul est terminé mais que les coordonnées
        // restent indisponibles (GPS refusé/échoué), on affiche juste la
        // carte centrée sur Bamako plutôt qu'un spinner bloqué.
        if (widget.enCalcul || (pointsPrets && _chargementTrace))
          Container(
            color: Colors.black.withValues(alpha: 0.15),
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatPrix extends StatelessWidget {
  final IconData icone;
  final String label, valeur;
  final bool accent;
  const _StatPrix({
    required this.icone,
    required this.label,
    required this.valeur,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 14, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          valeur,
          style: TextStyle(
            color: accent ? TaamaColors.accentMint : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: accent ? 16 : 18,
          ),
        ),
      ],
    );
  }
}