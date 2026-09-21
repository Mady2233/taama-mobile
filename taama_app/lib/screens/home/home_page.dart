// lib/screens/home/home_page.dart
//
// Pont entre les services/API existants et le widget purement
// présentationnel HomeScreen v3 (voir home_screen.dart) — remplace
// EcranCarte comme contenu de l'onglet Accueil (accueil_screen.dart).
// EcranCarte reste disponible sous home_screen_legacy.dart (non
// supprimée), toujours utilisée directement par services_screen.dart.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_service.dart';
import '../../services/routing_service.dart';
import '../courier_screen.dart';
import '../portefeuille_screen.dart';
import '../profil_screen.dart';
import '../recherche_screen.dart';
import '../resultats_recherche_screen.dart';
import 'home_screen.dart';

/// Durée de validité du cache client sur les temps de trajet OSRM des
/// suggestions — évite un appel OSRM par ouverture de l'accueil, sans
/// jamais montrer une durée trop vieille pour être pertinente.
const Duration _dureeCacheOsrm = Duration(minutes: 5);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _EntreeCacheDuree {
  _EntreeCacheDuree(this.dureeMinutes, this.calculeeLe);
  final int? dureeMinutes;
  final DateTime calculeeLe;

  bool get expiree => DateTime.now().difference(calculeeLe) > _dureeCacheOsrm;
}

class _HomePageState extends State<HomePage> {
  String? _prenom;
  // ⚠️ Aucune source actuelle (pas de reverse-geocoding dans l'app) — voir
  // rapport. HomeScreen gère déjà null proprement (ligne masquée).
  final String? _quartier = null;
  int _soldeFcfa = 0;
  bool _chargementConducteurs = true;
  List<ConducteurProche> _conducteurs = [];
  List<SuggestionDestination> _suggestions = [];
  LatLng? _positionClient;

  final Map<String, _EntreeCacheDuree> _cacheDurees = {};

  @override
  void initState() {
    super.initState();
    _chargerProfil();
    _chargerSolde();
    _initialiserPositionPuisDependances();
  }

  // ─── Chargement des données ───

  Future<void> _chargerProfil() async {
    try {
      final profil = await ApiService.monProfil();
      if (!mounted) return;
      setState(() => _prenom = (profil['first_name'] as String?)?.trim());
    } catch (e) {
      debugPrint('[HomePage] Erreur chargement profil : $e');
    }
  }

  Future<void> _chargerSolde() async {
    try {
      final solde = await ApiService.monSolde();
      if (!mounted) return;
      setState(() => _soldeFcfa = solde);
    } catch (e) {
      debugPrint('[HomePage] Erreur chargement solde : $e');
    }
  }

  /// Position d'abord (nécessaire pour les conducteurs proches ET les
  /// durées OSRM des suggestions), puis tout ce qui en dépend.
  Future<void> _initialiserPositionPuisDependances() async {
    await _obtenirPosition();
    await Future.wait([
      _chargerConducteursProches(),
      _chargerSuggestions(),
    ]);
  }

  Future<void> _obtenirPosition({bool forcer = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _positionClient = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint('[HomePage] Erreur position GPS : $e');
    }
  }

  /// ⚠️ Même limite que v2 : le backend n'expose pas de "type" d'adresse
  /// (domicile/travail), seulement un libellé libre — déduction
  /// heuristique, cosmétique uniquement (choix de l'icône).
  TypeAdresse _deduireType(String libelle) {
    final l = libelle.toLowerCase();
    if (l.contains('domicile') || l.contains('maison')) return TypeAdresse.domicile;
    if (l.contains('travail') || l.contains('bureau')) return TypeAdresse.travail;
    return TypeAdresse.autre;
  }

  Future<void> _chargerSuggestions() async {
    try {
      final brut = await ApiService.mesAdressesFavorites();
      if (!mounted) return;

      final suggestions = <SuggestionDestination>[];
      for (final a in brut) {
        final map = a as Map<String, dynamic>;
        final id = map['id'].toString();
        final libelle = (map['libelle'] ?? '').toString();
        final lat = (map['latitude'] as num?)?.toDouble();
        final lng = (map['longitude'] as num?)?.toDouble();

        suggestions.add(SuggestionDestination(
          id: id,
          libelle: libelle,
          type: _deduireType(libelle),
          dureeMinutes: await _dureeAvecCache(id, lat, lng),
        ));
      }
      if (!mounted) return;
      setState(() => _suggestions = suggestions);
    } catch (e) {
      debugPrint('[HomePage] Erreur chargement suggestions : $e');
    }
  }

  /// Cache 5 min sur les durées OSRM (étape 6 du brief) — un même
  /// favori ne redéclenche pas d'appel OSRM à chaque ouverture de
  /// l'accueil dans la fenêtre de validité.
  Future<int?> _dureeAvecCache(String id, double? lat, double? lng) async {
    final position = _positionClient;
    if (lat == null || lng == null || position == null) return null;

    final entree = _cacheDurees[id];
    if (entree != null && !entree.expiree) return entree.dureeMinutes;

    final duree = await RoutingService.dureeMinutesVers(
      depart: position,
      arrivee: LatLng(lat, lng),
    );
    _cacheDurees[id] = _EntreeCacheDuree(duree, DateTime.now());
    return duree;
  }

  ConducteurProche _conducteurDepuisJson(Map<String, dynamic> c) {
    final noteBrute = c['note'];
    return ConducteurProche(
      id: c['id'].toString(),
      nomCourt: (c['nom_court'] ?? '').toString(),
      position: LatLng((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble()),
      // null si le chauffeur n'a pas (encore) de photo de profil —
      // PhotoAvatar retombe proprement sur les initiales dans ce cas.
      urlPhoto: c['photo_profil'] as String?,
      note: noteBrute == null ? null : double.tryParse(noteBrute.toString()),
      modeleVehicule: c['vehicule'] as String?,
      minutesAvant: c['temps_minutes'] as int?,
      estMoto: c['type_transport'] == 'Moto',
    );
  }

  /// Seule donnée réactualisée par le pull-to-refresh de HomeScreen pour
  /// les conducteurs — réel, l'endpoint existe et fonctionne déjà.
  Future<void> _chargerConducteursProches() async {
    if (mounted) setState(() => _chargementConducteurs = true);
    final position = _positionClient;
    if (position == null) {
      if (mounted) setState(() => _chargementConducteurs = false);
      return;
    }
    try {
      final brut = await ApiService.conducteursProches(
        lat: position.latitude,
        lng: position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _conducteurs = brut.map((c) => _conducteurDepuisJson(c as Map<String, dynamic>)).toList();
        _chargementConducteurs = false;
      });
    } catch (e) {
      debugPrint('[HomePage] Erreur chargement conducteurs proches : $e');
      if (mounted) setState(() => _chargementConducteurs = false);
    }
  }

  /// onActualiser (étape 4) : "recharge conducteurs + tarifs". Les tarifs
  /// n'ont aujourd'hui aucune source réelle (endpoint pas encore créé,
  /// voir ApiService.tarifsMinServices) — rien à recharger de ce côté
  /// tant qu'il n'existe pas. À décommenter/brancher quand il existera.
  Future<void> _actualiser() async {
    await _chargerConducteursProches();
    // await _chargerTarifsMin(); // TODO: une fois l'endpoint créé.
  }

  // ─── Navigation ───

  Future<void> _ouvrirRecherche({String? typePreselectionne}) async {
    final resultat = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const EcranRecherche()),
    );
    if (resultat == null || !mounted) return;
    _ouvrirDemandeInstantanee(resultat, typePreselectionne: typePreselectionne);
  }

  void _ouvrirDemandeInstantanee(String destination, {String? typePreselectionne}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EcranDemandeInstantanee(
          destination: destination,
          typePreselectionne: typePreselectionne,
        ),
      ),
    );
  }

  Future<void> _ajouterAdresse() async {
    final libelleController = TextEditingController();
    final adresseController = TextEditingController();

    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle adresse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: libelleController,
              decoration: const InputDecoration(labelText: 'Libellé (ex. Domicile)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: adresseController,
              decoration: const InputDecoration(labelText: 'Adresse'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    final libelle = libelleController.text.trim();
    final adresse = adresseController.text.trim();
    if (libelle.isEmpty || adresse.isEmpty) return;

    try {
      await ApiService.enregistrerAdresseFavorite(libelle: libelle, adresse: adresse);
      await _chargerSuggestions();
    } catch (e) {
      debugPrint('[HomePage] Erreur enregistrement adresse favorite : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      prenom: _prenom,
      quartier: _quartier,
      // ⚠️ Aucune source actuelle, voir rapport.
      urlPhotoProfil: null,
      soldeFcfa: _soldeFcfa,
      // ⚠️ Endpoint tarifs-min pas encore créé (étape 5) — jamais de prix
      // inventé, la section "Choisir un service" reste vide en attendant.
      services: const [],
      suggestions: _suggestions,
      conducteursProches: _conducteurs,
      positionClient: _positionClient,
      chargementConducteurs: _chargementConducteurs,
      // ⚠️ Endpoint dernière course pas encore créé (étape 5).
      derniereCourse: null,
      onChercherDestination: () => _ouvrirRecherche(),
      onSuggestion: (s) => _ouvrirDemandeInstantanee(s.libelle),
      onAjouterAdresse: _ajouterAdresse,
      onService: (s) => _ouvrirRecherche(typePreselectionne: s.code),
      onReserver: () => _ouvrirRecherche(),
      onColis: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EcranCourier()),
      ),
      onPortefeuille: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EcranPortefeuille(estChauffeur: false)),
      ),
      onProfil: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EcranProfil()),
      ),
      // ⚠️ _BandeCarte (home_screen.dart) est un StatelessWidget sans
      // MapController exposé — FlutterMap.initialCenter n'est appliqué
      // qu'à la création du widget, pas de façon réactive. Cette méthode
      // rafraîchit bien _positionClient, mais un recentrage visuel garanti
      // demanderait d'exposer un MapController depuis home_screen.dart
      // (fichier fourni, copié tel quel — hors périmètre de ce lot).
      onRecentrerCarte: () => _obtenirPosition(forcer: true),
      // Jamais invoqué tant que derniereCourse est null (HomeScreen ne
      // montre la carte "refaire" que si non-null) — câblé pour quand
      // l'endpoint existera.
      onRefaireCourse: null,
      // ⚠️ Aucune fonctionnalité de dictée vocale dans l'app — optionnel,
      // laissé à null plutôt que simulé.
      onDicterDestination: null,
      onActualiser: _actualiser,
    );
  }
}
