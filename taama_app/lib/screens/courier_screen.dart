import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../theme/couleurs_taama.dart';
import 'chat_screen.dart';

class EcranCourier extends StatefulWidget {
  const EcranCourier({super.key});

  @override
  State<EcranCourier> createState() => _EcranCourierState();
}

class _EcranCourierState extends State<EcranCourier> {
  // Formulaire
  final _collecteController = TextEditingController();
  final _livraisonController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _telephoneDestinataireController = TextEditingController();
  LatLng? _pointCollecte;
  LatLng? _pointLivraison;
  double _distanceKm = 5.0;
  String _categorie = 'colis';

  static const _categories = [
    ('colis', '📦', 'Colis'),
    ('repas', '🍽️', 'Repas'),
    ('document', '📄', 'Document'),
  ];

  // Commande
  bool _enChargement = false;
  bool _enPaiement = false;
  Map<String, dynamic>? _commande;

  // Suivi
  Timer? _timerPolling;
  LatLng? _positionLivreur;
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _collecteController.dispose();
    _livraisonController.dispose();
    _descriptionController.dispose();
    _telephoneDestinataireController.dispose();
    _timerPolling?.cancel();
    _locationService.arreter();
    super.dispose();
  }

  // ─── Sélection GPS des adresses ───

  Future<void> _selectionnerPoint({required bool estCollecte}) async {
    final point = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => _EcranSelectionAdresse(
          titre: estCollecte ? 'Point de collecte' : 'Point de livraison',
        ),
      ),
    );
    if (point == null || !mounted) return;

    setState(() {
      if (estCollecte) {
        _pointCollecte = point;
        _collecteController.text =
            '${point.latitude.toStringAsFixed(4)}, '
            '${point.longitude.toStringAsFixed(4)}';
      } else {
        _pointLivraison = point;
        _livraisonController.text =
            '${point.latitude.toStringAsFixed(4)}, '
            '${point.longitude.toStringAsFixed(4)}';
      }
      // Recalcule la distance si les deux points sont sélectionnés
      if (_pointCollecte != null && _pointLivraison != null) {
        const calc = Distance();
        _distanceKm = calc.as(
          LengthUnit.Kilometer,
          _pointCollecte!,
          _pointLivraison!,
        );
      }
    });
  }

  int get _prix => (_distanceKm * 100 + 200).round().clamp(500, 999999);

  // ─── Commande ───

  Future<void> _commander() async {
    if (_collecteController.text.trim().isEmpty ||
        _livraisonController.text.trim().isEmpty ||
        _descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remplis tous les champs')));
      return;
    }

    setState(() => _enChargement = true);
    try {
      final resultat = await ApiService.creerCourier(
        adresseCollecte: _collecteController.text.trim(),
        adresseLivraison: _livraisonController.text.trim(),
        descriptionColis: _descriptionController.text.trim(),
        categorie: _categorie,
        telephoneDestinataire: _telephoneDestinataireController.text.trim(),
        distanceKm: _distanceKm,
        latCollecte: _pointCollecte?.latitude,
        lngCollecte: _pointCollecte?.longitude,
        latLivraison: _pointLivraison?.latitude,
        lngLivraison: _pointLivraison?.longitude,
      );

      if (!mounted) return;
      setState(() => _commande = resultat);
      _demarrerSuivi();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            e.toString().replaceAll('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _enChargement = false);
    }
  }

  Future<void> _payer() async {
    setState(() => _enPaiement = true);
    try {
      await ApiService.payerCourier(_commande!['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paiement effectué depuis ton solde Taama')));
      final detail = await ApiService.detailCourier(_commande!['id'] as int);
      if (!mounted) return;
      setState(() => _commande = detail);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            e.toString().replaceAll('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _enPaiement = false);
    }
  }

  // ─── Suivi GPS livreur ───

  void _demarrerSuivi() {
    final courierId = _commande!['id'] as int;
    final roomGps = _commande!['room_gps']?.toString() ??
        'courier_gps_$courierId';

    // Écoute la position GPS du livreur
    _locationService.ecouterPosition(roomGps, (lat, lng) {
      if (!mounted) return;
      final nouvPos = LatLng(lat, lng);
      setState(() => _positionLivreur = nouvPos);
      try {
        _mapController.move(nouvPos, 15.0);
      } catch (_) {}
    });

    // Polling statut toutes les 5s
    _timerPolling = Timer.periodic(
      const Duration(seconds: 5),
      (_) async {
        try {
          final detail = await ApiService.detailCourier(courierId);
          if (!mounted) return;
          setState(() => _commande = detail);
          if (detail['statut'] == 'livre' ||
              detail['statut'] == 'annule') {
            _timerPolling?.cancel();
            _locationService.arreter();
          }
        } catch (_) {}
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      appBar: AppBar(
        title: const Text('📦 Courier',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          if (_commande != null)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EcranChat(
                    roomName: _commande!['room_chat']?.toString() ??
                        'courier_${_commande!['id']}',
                    titreConversation: 'Livreur',
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _commande != null
          ? _buildSuivi()
          : _buildFormulaire(),
    );
  }

  // ─── FORMULAIRE ───

  Widget _buildFormulaire() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bannière
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.orange, Color(0xFFFF8C00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Text('📦', style: TextStyle(fontSize: 36)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Taama Courier',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                      Text('Livraison rapide à Bamako',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Formulaire
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 8)
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Informations de livraison',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),

                // Catégorie de livraison
                Row(
                  children: _categories.map((c) {
                    final (valeur, emoji, label) = c;
                    final estSelectionne = _categorie == valeur;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _categorie = valeur),
                        child: Container(
                          margin: EdgeInsets.only(
                              right: valeur != _categories.last.$1 ? 8 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: estSelectionne
                                ? Colors.orange.shade100
                                : CouleursTaama.sable,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: estSelectionne
                                  ? Colors.orange
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(emoji, style: const TextStyle(fontSize: 20)),
                              const SizedBox(height: 2),
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: estSelectionne
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: estSelectionne
                                      ? Colors.orange.shade800
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Collecte
                _ChampAdresse(
                  controller: _collecteController,
                  label: '📍 Point de collecte',
                  hint: 'Où récupérer le colis ?',
                  estSelectionne: _pointCollecte != null,
                  onSelectGPS: () =>
                      _selectionnerPoint(estCollecte: true),
                ),
                const SizedBox(height: 12),

                // Livraison
                _ChampAdresse(
                  controller: _livraisonController,
                  label: '🏁 Point de livraison',
                  hint: 'Où livrer le colis ?',
                  estSelectionne: _pointLivraison != null,
                  onSelectGPS: () =>
                      _selectionnerPoint(estCollecte: false),
                ),
                const SizedBox(height: 12),

                // Description
                TextField(
                  controller: _descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: '📦 Description du colis',
                    hintText:
                        'Ex: Documents administratifs, vêtements...',
                    filled: true,
                    fillColor: CouleursTaama.sable,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Téléphone du destinataire (optionnel)
                TextField(
                  controller: _telephoneDestinataireController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: '📱 Numéro du destinataire (optionnel)',
                    hintText: 'S\'il a un compte Taama, il pourra payer lui-même',
                    filled: true,
                    fillColor: CouleursTaama.sable,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Mini-carte si deux points sélectionnés
                if (_pointCollecte != null && _pointLivraison != null)
                  _MiniCarte(
                    pointCollecte: _pointCollecte!,
                    pointLivraison: _pointLivraison!,
                  ),

                const SizedBox(height: 12),

                // Prix estimé
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.payments_outlined,
                          color: Colors.orange),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Prix estimé',
                                style: TextStyle(
                                    color: Colors.orange, fontSize: 12)),
                            Text('$_prix FCFA',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: Colors.orange)),
                          ],
                        ),
                      ),
                      Text(
                        '${_distanceKm.toStringAsFixed(1)} km',
                        style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Bouton commander
          ElevatedButton.icon(
            onPressed: _enChargement ? null : _commander,
            icon: const Icon(Icons.local_shipping),
            label: _enChargement
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text('Commander — $_prix FCFA',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── SUIVI ───

  Widget _buildSuivi() {
    final statut = _commande!['statut']?.toString() ?? '';
    final livreur =
        _commande!['livreur'] as Map<String, dynamic>?;
    final aPhoto = _commande!['photo_livraison'] == true;

    return Column(
      children: [
        // Carte de suivi
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _pointCollecte ??
                      const LatLng(12.6392, -8.0029),
                  initialZoom: 13.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.taama.taama_app',
                    errorTileCallback: (t, e, s) {},
                  ),
                  MarkerLayer(
                    markers: [
                      // Point de collecte
                      if (_pointCollecte != null)
                        Marker(
                          point: _pointCollecte!,
                          width: 40, height: 40,
                          child: const _MarqueurPoint(
                              emoji: '📍',
                              couleur: Colors.green),
                        ),
                      // Point de livraison
                      if (_pointLivraison != null)
                        Marker(
                          point: _pointLivraison!,
                          width: 40, height: 40,
                          child: const _MarqueurPoint(
                              emoji: '🏁',
                              couleur: Colors.red),
                        ),
                      // Position livreur (temps réel)
                      if (_positionLivreur != null)
                        Marker(
                          point: _positionLivreur!,
                          width: 48, height: 48,
                          child: const _MarqueurPoint(
                              emoji: '🛵',
                              couleur: Colors.orange),
                        ),
                    ],
                  ),
                ],
              ),

              // Info livreur (overlay haut)
              if (livreur != null)
                Positioned(
                  top: 12, left: 12, right: 12,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12,
                            blurRadius: 8)
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Text(
                            livreur['nom']?.toString()
                                .substring(0, 1)
                                .toUpperCase() ?? '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                livreur['nom']?.toString() ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '${livreur['vehicule'] ?? ''} • '
                                '⭐ ${livreur['note'] ?? '5.0'}',
                                style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        // Bouton chat
                        IconButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EcranChat(
                                roomName: _commande![
                                        'room_chat']
                                    ?.toString() ??
                                    'courier_${_commande!['id']}',
                                titreConversation:
                                    livreur['nom']?.toString() ??
                                        'Livreur',
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline,
                              color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Panel bas : statut + étapes
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 12)
            ],
          ),
          child: Column(
            children: [
              // Étapes de progression
              _BarreProgression(statut: statut),
              const SizedBox(height: 16),

              // Photo de livraison si disponible
              if (aPhoto)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Preuve de livraison disponible',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_commande!['peut_payer'] == true) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _enPaiement ? null : _payer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _enPaiement
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text('Payer ${_commande!['prix']} FCFA',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],

              if (statut == 'livre') ...[
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => setState(() => _commande = null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Nouvelle livraison'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── WIDGETS AUXILIAIRES ───

class _ChampAdresse extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool estSelectionne;
  final VoidCallback onSelectGPS;

  const _ChampAdresse({
    required this.controller,
    required this.label,
    required this.hint,
    required this.estSelectionne,
    required this.onSelectGPS,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              filled: true,
              fillColor: CouleursTaama.sable,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSelectGPS,
          child: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: estSelectionne
                  ? Colors.green.shade100
                  : Colors.orange.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              estSelectionne ? Icons.check : Icons.map_outlined,
              color: estSelectionne ? Colors.green : Colors.orange,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniCarte extends StatelessWidget {
  final LatLng pointCollecte;
  final LatLng pointLivraison;

  const _MiniCarte({
    required this.pointCollecte,
    required this.pointLivraison,
  });

  @override
  Widget build(BuildContext context) {
    final centre = LatLng(
      (pointCollecte.latitude + pointLivraison.latitude) / 2,
      (pointCollecte.longitude + pointLivraison.longitude) / 2,
    );

    return Container(
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: centre,
            initialZoom: 13.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.taama.taama_app',
              errorTileCallback: (t, e, s) {},
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: pointCollecte,
                  width: 32, height: 32,
                  child: const _MarqueurPoint(
                      emoji: '📍', couleur: Colors.green),
                ),
                Marker(
                  point: pointLivraison,
                  width: 32, height: 32,
                  child: const _MarqueurPoint(
                      emoji: '🏁', couleur: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MarqueurPoint extends StatelessWidget {
  final String emoji;
  final Color couleur;

  const _MarqueurPoint({required this.emoji, required this.couleur});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: couleur, width: 2),
        boxShadow: [BoxShadow(
          color: couleur.withValues(alpha: 0.3),
          blurRadius: 4,
        )],
      ),
      child: Center(
        child: Text(emoji, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

class _BarreProgression extends StatelessWidget {
  final String statut;

  const _BarreProgression({required this.statut});

  @override
  Widget build(BuildContext context) {
    final etapes = [
      ('livreur_assigne', '✅ Assigné'),
      ('en_collecte', '🚗 Collecte'),
      ('en_livraison', '📦 Livraison'),
      ('livre', '🎉 Livré'),
    ];

    final indexActuel =
        etapes.indexWhere((e) => e.$1 == statut);

    return Column(
      children: [
        // Barre de progression
        Row(
          children: etapes.asMap().entries.map((entry) {
            final index = entry.key;
            final estPasse = index <= indexActuel;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(
                    right: index < etapes.length - 1 ? 4 : 0),
                decoration: BoxDecoration(
                  color: estPasse ? Colors.orange : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: etapes.asMap().entries.map((entry) {
            final index = entry.key;
            final (_, label) = entry.value;
            final estActuel = index == indexActuel;
            final estPasse = index < indexActuel;
            return Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: estActuel
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: estActuel
                    ? Colors.orange
                    : estPasse
                        ? Colors.green
                        : Colors.grey,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// Écran de sélection d'adresse sur la carte
class _EcranSelectionAdresse extends StatefulWidget {
  final String titre;
  const _EcranSelectionAdresse({required this.titre});

  @override
  State<_EcranSelectionAdresse> createState() =>
      _EcranSelectionAdresseState();
}

class _EcranSelectionAdresseState
    extends State<_EcranSelectionAdresse> {
  LatLng? _point;
  final MapController _ctrl = MapController();
  bool _chargement = true;

  static const _bamako = LatLng(12.6392, -8.0029);

  @override
  void initState() {
    super.initState();
    _centrerGPS();
  }

  Future<void> _centrerGPS() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (!mounted) return;
      final p = LatLng(pos.latitude, pos.longitude);
      setState(() { _point = p; _chargement = false; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ctrl.move(p, 15.0);
      });
    } catch (_) {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titre),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          if (_point != null)
            TextButton(
              onPressed: () => Navigator.pop(context, _point),
              child: const Text('Confirmer',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _ctrl,
            options: MapOptions(
              initialCenter: _bamako,
              initialZoom: 14.0,
              onTap: (_, p) => setState(() => _point = p),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.taama.taama_app',
                errorTileCallback: (t, e, s) {},
              ),
              if (_point != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _point!,
                      width: 48, height: 48,
                      child: const Icon(Icons.location_pin,
                          color: Colors.orange, size: 48),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 12, left: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6)
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Text('Tape sur la carte pour sélectionner',
                      style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
          if (_chargement)
            const Center(child: CircularProgressIndicator(
                color: Colors.orange)),
        ],
      ),
    );
  }
}
