import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'recherche_screen.dart';
import 'resultats_recherche_screen.dart';
import 'profil_screen.dart';
import 'courier_screen.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';
import '../widgets/widget_avatar_conducteur.dart';

/// Troisième écran : La carte principale de l'application
class EcranCarte extends StatefulWidget {
  final String? typeVehiculeInitial;
  const EcranCarte({super.key, this.typeVehiculeInitial});

  @override
  State<EcranCarte> createState() => _EcranCarteState();
}

class _EcranCarteState extends State<EcranCarte> {
  // Mes coordonnées de départ par défaut (Bamako) au cas où le GPS met du temps
  final LatLng _centreParDefaut = const LatLng(12.6392, -8.0029);

  // Mon contrôleur de carte pour pouvoir la manipuler (zoomer, centrer)
  final MapController _mapController = MapController();

  // Profil de l'utilisateur connecté, affiché dans le header
  Map<String, dynamic>? _profil;
  String _salutation = 'Bonjour !';
  String? _destinationChoisie;
  int? _solde;
  LatLng? _positionActuelle;

  List<Map<String, dynamic>> _conducteursProches = [];
  bool _chargementConducteurs = false;
  Timer? _timerRefreshConducteurs;

  @override
  void initState() {
    super.initState();
    _calculerSalutation();
    _chargerProfil();
    _chargerSolde();
    // Dès que l'écran se charge, je lance la recherche de ma position
    _obtenirPositionActuelle();
    _chargerConducteursProches();

    // Refresh automatique des conducteurs proches toutes les 30 secondes
    _timerRefreshConducteurs = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _chargerConducteursProches(),
    );

    // Si un type de véhicule a été présélectionné (venant de l'écran Services),
    // j'ouvre directement la recherche de destination pour ce véhicule.
    if (widget.typeVehiculeInitial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ouvrirDemandeInstantanee(typePreselectionne: widget.typeVehiculeInitial);
      });
    }
  }

  @override
  void dispose() {
    _timerRefreshConducteurs?.cancel();
    super.dispose();
  }

  void _calculerSalutation() {
    final heure = DateTime.now().hour;
    _salutation = heure < 12
        ? 'Bonjour'
        : heure < 18
            ? 'Bon après-midi'
            : 'Bonsoir';
  }

  Future<void> _chargerProfil() async {
    try {
      final profil = await ApiService.monProfil();
      if (!mounted) return;
      setState(() => _profil = profil);
    } catch (e) {
      debugPrint('Erreur de chargement du profil : $e');
    }
  }

  Future<void> _chargerSolde() async {
    try {
      final solde = await ApiService.monSolde();
      if (mounted) setState(() => _solde = solde);
    } catch (_) {}
  }

  Future<void> _chargerConducteursProches() async {
    if (_positionActuelle == null) {
      // Attendre la position GPS
      await Future.delayed(const Duration(seconds: 2));
      if (_positionActuelle == null) return;
    }
    if (!mounted) return;

    setState(() => _chargementConducteurs = true);
    try {
      final conducteurs = await ApiService.conducteursProches(
        lat: _positionActuelle!.latitude,
        lng: _positionActuelle!.longitude,
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(() {
        _conducteursProches = conducteurs
            .map((c) => c as Map<String, dynamic>)
            .toList();
      });
    } on TimeoutException {
      debugPrint('[Carte] Timeout chargement conducteurs');
    } catch (e) {
      debugPrint('[Carte] Erreur conducteurs proches : $e');
    } finally {
      if (mounted) setState(() => _chargementConducteurs = false);
    }
  }

  String get _prenom {
    final p = _profil?['first_name']?.toString() ?? '';
    final n = _profil?['telephone']?.toString() ?? '';
    return p.isNotEmpty ? p : n;
  }

  String get _initiales {
    final nom = '${_profil?['first_name'] ?? ''} ${_profil?['last_name'] ?? ''}'.trim();
    if (nom.isEmpty) return '?';
    return nom.split(' ').take(2)
        .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
        .join();
  }

  /// Fonction asynchrone pour récupérer ma position GPS
  Future<void> _obtenirPositionActuelle() async {
    bool serviceActive;
    LocationPermission permission;

    // 1. Je vérifie si le service GPS du téléphone est activé
    serviceActive = await Geolocator.isLocationServiceEnabled();
    if (!serviceActive) {
      debugPrint('Les services de localisation sont désactivés.');
      return;
    }

    // 2. Je vérifie si l'utilisateur m'a donné la permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Les permissions de localisation sont refusées.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Les permissions sont définitivement refusées.');
      return;
    }

    // 3. Si tout est bon, je récupère ma position exacte
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, // Haute précision requise pour un VTC
      ),
    );

    if (!mounted) return;
    setState(() => _positionActuelle = LatLng(position.latitude, position.longitude));
    _chargerConducteursProches();

    // 4. Je déplace ma carte de façon dynamique vers ma vraie position
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      16.0, // Je zoome un peu plus fort (16.0) car c'est ma position exacte
    );
  }

  /// Ouvre le sélecteur de destination, puis va directement vers la demande
  /// instantanée — point d'entrée UNIQUE côté passager (dispatch pur, plus
  /// de recherche/réservation d'offres publiées).
  Future<void> _ouvrirDemandeInstantanee({String? typePreselectionne}) async {
    final resultat = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EcranRecherche()),
    );
    if (resultat == null || !mounted) return;
    setState(() => _destinationChoisie = resultat.toString());
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EcranDemandeInstantanee(
          destination: resultat?.toString() ?? '',
          typePreselectionne: typePreselectionne,
        ),
      ),
    );
  }

  void _afficherInfoConducteur(Map<String, dynamic> conducteur) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                AvatarConducteur(
                  photoUrl: conducteur['photo_profil'] as String?,
                  nom: conducteur['nom']?.toString() ?? '',
                  radius: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            conducteur['nom']?.toString() ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (conducteur['verifie'] == true) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified,
                                color: Colors.blue, size: 16),
                          ],
                        ],
                      ),
                      Text(
                        '${conducteur['vehicule'] ?? ''} • '
                        '⭐ ${conducteur['note'] ?? '5.0'}',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                      Text(
                        '${conducteur['distance_km']} km • '
                        '≈ ${conducteur['temps_minutes']} min',
                        style: const TextStyle(
                          color: CouleursTaama.terreCuite,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                // Lance directement une demande vers ce conducteur
                _ouvrirDemandeInstantanee();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CouleursTaama.terreCuite,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'Commander ce conducteur • ${conducteur['temps_minutes']} min',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ═══ HEADER GRADIENT ═══
          _buildHeader(),

          // ═══ SPLIT SCREEN ═══
          Expanded(
            flex: 5,
            child: Row(
              children: [
                // Carte (60% largeur)
                Expanded(
                  flex: 6,
                  child: _buildCarte(),
                ),
                // Liste conducteurs (40% largeur)
                Expanded(
                  flex: 4,
                  child: _buildListeConducteurs(),
                ),
              ],
            ),
          ),

          // ═══ PANEL BAS ═══
          _buildPanelBas(),
        ],
      ),
    );
  }

  // ─── HEADER GRADIENT ───
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1C2B4A), // indigo Taama
            Color(0xFF3D2B6B), // violet profond
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            children: [
              // Avatar initiales
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EcranProfil()),
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: CouleursTaama.terreCuite,
                  child: Text(
                    _initiales,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_salutation, $_prenom 👋',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 11, color: CouleursTaama.or),
                        const SizedBox(width: 2),
                        Text(
                          'Bamako, Mali',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Solde badge
              if (_solde != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.account_balance_wallet,
                          size: 14, color: CouleursTaama.or),
                      const SizedBox(width: 4),
                      Text(
                        '$_solde F',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              // Notification
              Stack(
                children: [
                  const Icon(Icons.notifications_outlined,
                      color: Colors.white, size: 24),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: CouleursTaama.terreCuite,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CARTE ───
  Widget _buildCarte() {
    return ClipRRect(
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _positionActuelle ?? _centreParDefaut,
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.taama.app',
                errorTileCallback: (tile, error, stack) {},
              ),
              // Marqueurs conducteurs
              MarkerLayer(
                markers: _conducteursProches.map((c) {
                  final estVoiture = c['type_transport'] == 'Voiture';
                  return Marker(
                    point: LatLng(
                      (c['lat'] as num).toDouble(),
                      (c['lng'] as num).toDouble(),
                    ),
                    width: 36,
                    height: 36,
                    child: GestureDetector(
                      onTap: () => _afficherInfoConducteur(c),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                            ),
                          ],
                          border: Border.all(
                            color: estVoiture
                                ? const Color(0xFF1C2B4A)
                                : CouleursTaama.terreCuite,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            estVoiture ? '🚗' : '🏍️',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              // Position actuelle (point pulsant)
              if (_positionActuelle != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _positionActuelle!,
                      width: 50,
                      height: 50,
                      child: const _MarqueurPulsant(),
                    ),
                  ],
                ),
            ],
          ),
          // Bouton géoloc
          Positioned(
            bottom: 8,
            right: 8,
            child: GestureDetector(
              onTap: _obtenirPositionActuelle,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.my_location,
                    color: Color(0xFF1C2B4A), size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── LISTE CONDUCTEURS (panneau droit) ───
  Widget _buildListeConducteurs() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1C2B4A),
            Color(0xFF2D3B5A),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          // Titre
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                const Icon(Icons.people, color: CouleursTaama.or, size: 14),
                const SizedBox(width: 4),
                Text(
                  '${_conducteursProches.length} proches',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Liste
          Expanded(
            child: _chargementConducteurs
                ? const Center(
                    child: CircularProgressIndicator(
                      color: CouleursTaama.or,
                      strokeWidth: 2,
                    ),
                  )
                : _conducteursProches.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('😴', style: TextStyle(fontSize: 24)),
                            const SizedBox(height: 4),
                            Text(
                              'Aucun\nconducteur',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _conducteursProches.length,
                        itemBuilder: (context, index) {
                          final c = _conducteursProches[index];
                          return GestureDetector(
                            onTap: () => _afficherInfoConducteur(c),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Row(
                                children: [
                                  AvatarConducteur(
                                    photoUrl: c['photo_profil'] as String?,
                                    nom: c['nom']?.toString() ?? '',
                                    radius: 14,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c['nom']?.toString() ?? '',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          maxLines: 1,
                                        ),
                                        Row(
                                          children: [
                                            const Icon(Icons.star,
                                                size: 10,
                                                color: CouleursTaama.or),
                                            const SizedBox(width: 2),
                                            Text(
                                              c['note']?.toString() ?? '5.0',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.7),
                                                fontSize: 10,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${c['temps_minutes']}min',
                                              style: const TextStyle(
                                                color: CouleursTaama.terreCuite,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (c['verifie'] == true)
                                    const Icon(Icons.verified,
                                        color: Colors.blue, size: 12),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          // Bouton rafraîchir
          GestureDetector(
            onTap: _chargerConducteursProches,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: CouleursTaama.terreCuite.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text('Actualiser',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── PANEL BAS ───
  Widget _buildPanelBas() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: GestureDetector(
              onTap: () async {
                final resultat = await Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => const EcranRecherche(),
                    transitionsBuilder: (_, anim, __, child) =>
                        SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 1),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOut,
                          )),
                          child: child,
                        ),
                  ),
                );
                if (resultat != null && mounted) {
                  setState(() => _destinationChoisie = resultat.toString());
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EcranDemandeInstantanee(destination: resultat.toString()),
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1C2B4A), Color(0xFF3D2B6B)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1C2B4A).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _destinationChoisie ?? 'Où allez-vous ?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.mic_outlined,
                        color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
          ),
          // Boutons rapides
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _BoutonRapide(
                  emoji: '⚡',
                  label: 'Instantané',
                  couleur: CouleursTaama.terreCuite,
                  onTap: () => _ouvrirDemandeInstantanee(),
                ),
                _BoutonRapide(
                  emoji: '📅',
                  label: 'Réserver',
                  couleur: CouleursTaama.indigo,
                  onTap: () => _ouvrirDemandeInstantanee(),
                ),
                _BoutonRapide(
                  emoji: '📦',
                  label: 'Courier',
                  couleur: Colors.orange,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const EcranCourier())),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget bouton rapide compact : emoji dans un carré + libellé.
class _BoutonRapide extends StatelessWidget {
  final String emoji;
  final String label;
  final Color couleur;
  final VoidCallback onTap;

  const _BoutonRapide({
    required this.emoji,
    required this.label,
    required this.couleur,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: couleur.withValues(alpha: 0.3),
              ),
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: couleur,
            ),
          ),
        ],
      ),
    );
  }
}

/// Marqueur de position GPS : un point indigo dont l'anneau pulse en continu.
class _MarqueurPulsant extends StatefulWidget {
  const _MarqueurPulsant();

  @override
  State<_MarqueurPulsant> createState() => _MarqueurPulsantState();
}

class _MarqueurPulsantState extends State<_MarqueurPulsant>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          // Cercle pulsant externe
          Container(
            width: 60 * _anim.value,
            height: 60 * _anim.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CouleursTaama.indigo.withValues(
                  alpha: 0.2 * (1 - _anim.value + 0.6)),
            ),
          ),
          // Point central
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CouleursTaama.indigo,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: CouleursTaama.indigo.withValues(alpha: 0.4),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
