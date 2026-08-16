import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';
import '../widgets/widget_choix_vehicule.dart';
import 'suivi_demande_screen.dart';

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
  int? _prixEstimeVoiture;
  int? _prixEstimeMoto;
  String? _erreur;
  Map<String, dynamic>? _detailPrixVoiture;
  Map<String, dynamic>? _detailPrixMoto;
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

  @override
  void initState() {
    super.initState();
    _calculerDistanceAuto();
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
      final dest = Uri.encodeComponent(
          '${widget.destination}, Bamako, Mali');
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?q=$dest&format=json&limit=1');
      final reponse = await http.get(url, headers: {
        'User-Agent': 'TaamaApp/1.0',
      }).timeout(const Duration(seconds: 10));

      double latDest = 12.6392; // Bamako par défaut
      double lngDest = -8.0029;
      // Distinct de "latDest/lngDest sont les vraies coordonnées" : les
      // valeurs par défaut ci-dessus servent à l'estimation de distance
      // même si le géocodage échoue, mais ne doivent JAMAIS être envoyées
      // au backend comme position de destination (ça guiderait le
      // conducteur vers le centre de Bamako au lieu de la vraie adresse).
      bool geocodageReussi = false;

      if (reponse.statusCode == 200) {
        final res = jsonDecode(reponse.body) as List;
        if (res.isNotEmpty) {
          latDest = double.parse(res[0]['lat'].toString());
          lngDest = double.parse(res[0]['lon'].toString());
          geocodageReussi = true;
        }
      }

      // 3. Distance Haversine
      const R = 6371.0;
      final dLat = _rad(latDest - position.latitude);
      final dLng = _rad(lngDest - position.longitude);
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(_rad(position.latitude)) *
              math.cos(_rad(latDest)) *
              math.sin(dLng / 2) *
              math.sin(dLng / 2);
      final distance = R * 2 * math.asin(math.sqrt(a.clamp(0, 1)));

      // 4. Prix calculés (estimation locale rapide, affichée immédiatement)
      final voiture = math.max(200, (distance * 150).round());
      final moto = math.max(150, (distance * 100).round());
      // Arrondi à 50 FCFA
      final prixV = ((voiture / 50).round() * 50);
      final prixM = ((moto / 50).round() * 50);

      setState(() {
        _distanceKm = double.parse(distance.toStringAsFixed(1));
        _prixEstimeVoiture = prixV;
        _prixEstimeMoto = prixM;
        _departLat = position.latitude;
        _departLng = position.longitude;
        if (geocodageReussi) {
          _destinationLat = latDest;
          _destinationLng = lngDest;
        }
        _calcul = false;
      });

      // 5. Récupère le détail de prix officiel (tarification dynamique)
      // depuis le backend pour les deux types de véhicule.
      try {
        final resVoiture = await ApiService.calculerDistanceGPS(
          latDepart: position.latitude,
          lonDepart: position.longitude,
          latArrivee: latDest,
          lonArrivee: lngDest,
          typeTransport: 'Voiture',
        );
        final resMoto = await ApiService.calculerDistanceGPS(
          latDepart: position.latitude,
          lonDepart: position.longitude,
          latArrivee: latDest,
          lonArrivee: lngDest,
          typeTransport: 'Moto',
        );
        if (mounted) {
          setState(() {
            _detailPrixVoiture = resVoiture['detail_prix'] as Map<String, dynamic>?;
            _detailPrixMoto = resMoto['detail_prix'] as Map<String, dynamic>?;
            if (_detailPrixVoiture != null) {
              _prixEstimeVoiture = _detailPrixVoiture!['prix_final'] as int;
            }
            if (_detailPrixMoto != null) {
              _prixEstimeMoto = _detailPrixMoto!['prix_final'] as int;
            }
          });
        }
      } catch (_) {
        // Le détail de prix backend est optionnel : l'estimation locale
        // affichée à l'étape 4 reste valable si l'appel échoue.
      }
    } catch (e) {
      setState(() {
        _distanceKm = 5.0; // Fallback
        _prixEstimeVoiture = 750;
        _prixEstimeMoto = 500;
        _calcul = false;
        _erreur = 'Distance estimée (GPS indisponible)';
      });
    }
  }

  double _rad(double deg) => deg * math.pi / 180;

  Future<void> _confirmer() async {
    if (_distanceKm == null) return;

    final choix = await afficherChoixVehicule(
      context,
      destination: widget.destination,
      distanceKm: _distanceKm!,
      typePreselectionne: widget.typePreselectionne,
      detailPrixVoiture: _detailPrixVoiture,
      detailPrixMoto: _detailPrixMoto,
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

    setState(() => _enChargement = true);
    try {
      final demande = await ApiService.creerDemandeInstantanee(
        destination: widget.destination,
        distanceKm: _distanceKm!,
        typeTransport: choix['type'] as String,
        dateHeurePlanifiee: dateHeurePlanifiee,
        departLat: _departLat,
        departLng: _departLng,
        destinationLat: _destinationLat,
        destinationLng: _destinationLng,
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
            builder: (_) => EcranSuiviDemande(
              demandeId: demande['id'] as int,
              destination: widget.destination,
              typeTransport: choix['type'] as String,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            e.toString().replaceAll('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
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
      body: SingleChildScrollView(
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
                  : Column(
                      children: [
                        if (_erreur != null)
                          Text(_erreur!,
                              style: const TextStyle(
                                  color: Colors.orange, fontSize: 11)),
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
                              label: '🚗 Voiture',
                              valeur: '$_prixEstimeVoiture FCFA',
                              accent: true,
                            ),
                            _StatPrix(
                              label: '🏍️ Moto',
                              valeur: '$_prixEstimeMoto FCFA',
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
                                color: Colors.white.withValues(alpha: 0.6),
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
            const SizedBox(height: 24),

            // Bouton confirmer
            ElevatedButton(
              onPressed: (_calcul || _enChargement) ? null : _confirmer,
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