import 'dart:convert';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/service_course.dart';
import '../services/api_service.dart';
import '../services/routing_service.dart';
import '../theme/couleurs_taama.dart';
import '../widgets/taama_map.dart' show TaamaMapTiles, attributionCarteTaama;
import '../widgets/widget_choix_vehicule.dart';
import 'course/suivi_course_page.dart';
import 'recherche_screen.dart';

/// Écran de demande instantanée : la distance est calculée automatiquement
/// (GPS + géocodage Nominatim + Haversine), puis le passager choisit son
/// véhicule et l'app cherche un conducteur disponible.
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

  /// Prix le plus bas parmi les devis disponibles — sert de référence à
  /// l'aperçu de réduction du code promo (la réduction réelle dépend du
  /// service choisi ensuite dans le sheet, revalidée à la création).
  int? get _prixReference {
    final services = _services;
    if (services == null) return null;
    final prix = services
        .where((s) => s.disponible && s.prix != null)
        .map((s) => s.prix!);
    return prix.isEmpty ? null : prix.reduce((a, b) => a < b ? a : b);
  }

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
        'User-Agent': 'TaamaApp/1.0',
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
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
  }

  @override
  void dispose() {
    _codePromoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      appBar: AppBar(
        title: const Text('Course instantanée',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: CouleursTaama.indigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Carte fixe en haut : itinéraire départ → destination, tracé
          // réel via OSRM (RoutingService) une fois les deux points connus.
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.32,
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Destination
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(
                    color: Colors.black12, blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: CouleursTaama.terreCuite
                          .withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_on,
                        color: CouleursTaama.terreCuite, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Destination',
                            style: TextStyle(
                                color: Colors.grey, fontSize: 11)),
                        Text(
                          widget.destination,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: CouleursTaama.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Arrêts intermédiaires
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _arrets.length; i++) ...[
                    Row(
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: CouleursTaama.indigo.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    color: CouleursTaama.indigo,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _arrets[i]['adresse']?.toString() ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        GestureDetector(
                          onTap: _recalculEnCours
                              ? null
                              : () => _supprimerArret(i),
                          child: Icon(Icons.close,
                              size: 18, color: Colors.grey.shade400),
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
                    GestureDetector(
                      onTap: _recalculEnCours ? null : _ajouterArret,
                      child: Row(
                        children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: CouleursTaama.terreCuite.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: _recalculEnCours
                                ? const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: CouleursTaama.terreCuite),
                                  )
                                : const Icon(Icons.add,
                                    color: CouleursTaama.terreCuite, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Ajouter un arrêt',
                            style: TextStyle(
                                color: CouleursTaama.terreCuite,
                                fontWeight: FontWeight.w600,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Distance + Prix calculés automatiquement
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    CouleursTaama.indigo,
                    const Color(0xFF3D2B6B),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: _calcul
                  ? const Column(
                      children: [
                        CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                        SizedBox(height: 10),
                        Text('Calcul de la distance...',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ],
                    )
                  : _distanceKm == null
                      // Jamais de distance/prix fabriqués (voir catch de
                      // _calculerDistanceAuto) : un état d'erreur explicite
                      // avec un vrai bouton pour relancer, plutôt qu'une
                      // estimation qui ne reposerait sur rien.
                      ? Column(
                          children: [
                            const Icon(Icons.location_off_rounded,
                                color: Colors.white70, size: 22),
                            const SizedBox(height: 6),
                            Text(
                              _erreur ??
                                  'Impossible de vous localiser — réessayez',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _calculerDistanceAuto,
                              icon: const Icon(Icons.refresh,
                                  size: 16, color: Colors.white),
                              label: const Text('Réessayer',
                                  style: TextStyle(color: Colors.white)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white70),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceAround,
                              children: [
                                _StatPrix(
                                  label: '📏 Distance',
                                  valeur:
                                      '${_distanceKm!.toStringAsFixed(1)} km',
                                ),
                                _StatPrix(
                                  label: '💰 À partir de',
                                  valeur: _prixReference != null
                                      ? '$_prixReference FCFA'
                                      : 'Indisponible',
                                  accent: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: _calculerDistanceAuto,
                              child: Text(
                                '🔄 Recalculer',
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11),
                              ),
                            ),
                          ],
                        ),
            ),
            const SizedBox(height: 16),

            // Planification
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.schedule,
                          color: CouleursTaama.indigo, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Planifier à l\'avance',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      Switch(
                        value: _planifier,
                        onChanged: (v) =>
                            setState(() => _planifier = v),
                        activeThumbColor: CouleursTaama.terreCuite,
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
                                initialDate: DateTime.now()
                                    .add(const Duration(hours: 1)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 30)),
                              );
                              if (d != null) {
                                setState(() => _datePlanifiee = d);
                              }
                            },
                            icon: const Icon(Icons.calendar_today,
                                size: 16),
                            label: Text(_datePlanifiee == null
                                ? 'Date'
                                : '${_datePlanifiee!.day}/${_datePlanifiee!.month}'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: CouleursTaama.indigo,
                              side: const BorderSide(
                                  color: CouleursTaama.indigo),
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
                              if (h != null) {
                                setState(() => _heurePlanifiee = h);
                              }
                            },
                            icon: const Icon(Icons.access_time,
                                size: 16),
                            label: Text(_heurePlanifiee == null
                                ? 'Heure'
                                : _heurePlanifiee!.format(context)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: CouleursTaama.indigo,
                              side: const BorderSide(
                                  color: CouleursTaama.indigo),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Code promo
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.local_offer_outlined,
                          color: CouleursTaama.indigo, size: 20),
                      SizedBox(width: 10),
                      Text('Code promo',
                          style: TextStyle(fontWeight: FontWeight.bold)),
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
                            // Un changement invalide l'aperçu précédent :
                            // évite d'afficher une réduction qui ne
                            // correspond plus au texte actuellement saisi.
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
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _verificationCodePromoEnCours
                            ? null
                            : _verifierCodePromo,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: CouleursTaama.indigo,
                          side: const BorderSide(color: CouleursTaama.indigo),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _verificationCodePromoEnCours
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: CouleursTaama.indigo),
                              )
                            : const Text('Vérifier'),
                      ),
                    ],
                  ),
                  if (_codePromoValide == true) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Code valide — réduction estimée de $_reductionCodePromo FCFA',
                          style: const TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ] else if (_codePromoValide == false) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _erreurCodePromo ?? 'Code invalide',
                            style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Bouton confirmer
            ElevatedButton(
              onPressed: (_calcul || _enChargement || _distanceKm == null ||
                      _services == null || _services!.isEmpty)
                  ? null
                  : _confirmer,
              style: ElevatedButton.styleFrom(
                backgroundColor: CouleursTaama.terreCuite,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 3,
                shadowColor:
                    CouleursTaama.terreCuite.withValues(alpha: 0.4),
              ),
              child: _enChargement
                  ? const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.flash_on, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _planifier
                              ? 'Planifier la course'
                              : 'Choisir mon véhicule',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ],
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
          padding: const EdgeInsets.fromLTRB(40, 40, 40, 20),
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

    return ClipRRect(
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: depart ?? _centreParDefaut,
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: TaamaMapTiles.clair,
                subdomains: TaamaMapTiles.subdomains,
                userAgentPackageName: TaamaMapTiles.userAgent,
                errorTileCallback: (tile, error, stack) {},
              ),
              attributionCarteTaama(),
              if (_trace != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _trace!,
                      strokeWidth: 4,
                      color: CouleursTaama.terreCuite,
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
                          color: CouleursTaama.indigo,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 6),
                          ],
                        ),
                        child: const Icon(Icons.trip_origin,
                            color: Colors.white, size: 14),
                      ),
                    ),
                  if (destination != null)
                    Marker(
                      point: destination,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on,
                          color: CouleursTaama.terreCuite, size: 40),
                    ),
                  for (var i = 0; i < widget.arrets.length; i++)
                    Marker(
                      point: widget.arrets[i],
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      child: Container(
                        decoration: BoxDecoration(
                          color: CouleursTaama.or,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 4),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Overlay de chargement uniquement pendant un calcul en cours (GPS
          // ou tracé OSRM) — si le calcul est terminé mais que les
          // coordonnées restent indisponibles (GPS refusé/échoué, voir le
          // repli dans _calculerDistanceAuto), on affiche juste la carte
          // centrée sur Bamako plutôt qu'un spinner bloqué indéfiniment.
          if (widget.enCalcul || (pointsPrets && _chargementTrace))
            Container(
              color: Colors.black.withValues(alpha: 0.15),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatPrix extends StatelessWidget {
  final String label, valeur;
  final bool accent;
  const _StatPrix({
    required this.label,
    required this.valeur,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          valeur,
          style: TextStyle(
            color: accent ? CouleursTaama.or : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: accent ? 15 : 18,
          ),
        ),
      ],
    );
  }
}