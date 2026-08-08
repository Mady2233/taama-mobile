import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../theme/couleurs_taama.dart';

/// Carte interactive pour sélectionner un point (départ ou arrivée).
/// Le conducteur tape sur la carte pour positionner le marqueur.
class EcranSelectionPoint extends StatefulWidget {
  final String titre;
  final LatLng? positionInitiale;

  const EcranSelectionPoint({
    super.key,
    required this.titre,
    this.positionInitiale,
  });

  @override
  State<EcranSelectionPoint> createState() => _EcranSelectionPointState();
}

class _EcranSelectionPointState extends State<EcranSelectionPoint> {
  final MapController _mapController = MapController();
  LatLng? _pointSelectionne;
  bool _chargement = true;

  // Centre par défaut : Bamako
  static const LatLng _bamako = LatLng(12.6392, -8.0029);

  @override
  void initState() {
    super.initState();
    _initialiser();
  }

  Future<void> _initialiser() async {
    LatLng position = widget.positionInitiale ?? _bamako;

    // Essaie de centrer sur la position GPS actuelle
    try {
      final gps = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      position = LatLng(gps.latitude, gps.longitude);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _pointSelectionne = position;
      _chargement = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(position, 14.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titre),
        backgroundColor: CouleursTaama.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_pointSelectionne != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _pointSelectionne),
              child: const Text(
                'Confirmer',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _bamako,
              initialZoom: 13.0,
              onTap: (tapPosition, point) {
                setState(() => _pointSelectionne = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.taama.taama_conducteur',
                errorTileCallback: (tile, error, stack) {},
              ),
              if (_pointSelectionne != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pointSelectionne!,
                      width: 56,
                      height: 56,
                      child: const Icon(
                        Icons.location_pin,
                        color: CouleursTaama.terreCuite,
                        size: 48,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Instruction
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app,
                      size: 20, color: CouleursTaama.indigo),
                  const SizedBox(width: 8),
                  Text(
                    'Tape sur la carte pour positionner le point',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_chargement)
            const Center(child: CircularProgressIndicator(
              color: CouleursTaama.terreCuite,
            )),
        ],
      ),
    );
  }
}
