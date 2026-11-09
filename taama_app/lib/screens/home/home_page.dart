// lib/screens/home/home_page.dart
//
// Pont entre les services/API existants et le widget purement
// présentationnel HomeScreen v4 (voir home_screen.dart) — contenu de
// l'onglet Accueil (accueil_screen.dart).
//
// Changements v4 :
// - chauffeurs proches rafraîchis toutes les 20 s, en pause quand l'app
//   passe en arrière-plan (le glissement des marqueurs a besoin de mises à
//   jour régulières) ; jamais deux requêtes en parallèle ;
// - lecture JSON défensive (une entrée mal formée est ignorée, pas de crash) ;
// - photo de profil acceptée uniquement en https ;
// - durées OSRM des favoris calculées en parallèle ;
// - dialogue « Nouvelle adresse » : contrôleurs libérés, longueurs limitées,
//   message si l'enregistrement échoue ;
// - solde rechargé si le paiement est réactivé à chaud ;
// - logs uniquement en debug.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../carte/fond_carte.dart';
import '../../models/verification_identite.dart';
import '../../services/api_service.dart';
import '../../services/config_app.dart';
import '../../services/routing_service.dart';
import '../../widgets/champ_adresse_lieu.dart';
import '../courier_screen.dart';
import '../course/suivi_course_page.dart';
import '../portefeuille_screen.dart';
import '../profil_screen.dart';
import '../recherche_screen.dart';
import '../../services/recherche_lieux.dart';
import '../resultats_recherche_screen.dart';
import '../verification_identite_page.dart';
import 'home_screen.dart';

/// Validité du cache des temps de trajet OSRM des favoris.
const Duration _dureeCacheOsrm = Duration(minutes: 5);

/// Fréquence de rafraîchissement des chauffeurs proches (écran visible).
const Duration _intervalleConducteurs = Duration(seconds: 20);

/// Statut (`StatutIdentite.name`) pour lequel l'invitation à vérifier son
/// identité a été fermée sur ce téléphone.
const String _cleInvitationIdentiteMasquee = 'invitation_identite_masquee';

const int _longueurMaxLibelle = 40;
const int _longueurMaxAdresse = 200;

/// Statuts qui ne sont PAS une course en cours (une demande qui n'en a aucun
/// est "active"). Filtrage par exclusion : plus robuste si un statut actif
/// est ajouté côté serveur. Statuts de DemandeInstantanee.STATUT_CHOICES
/// (backend) : planifiee, en_recherche, chauffeur_trouve, en_route,
/// client_a_bord, termine, annule. Une course planifiée n'est pas encore
/// en cours.
const Set<String> _statutsTermines = {'termine', 'annule', 'planifiee'};

/// Garde-fou : une demande non terminée plus vieille que ça est ignorée
/// (probablement bloquée côté serveur) pour ne pas ressortir un vieux bandeau.
const Duration _ageMaxCourseActive = Duration(hours: 24);

void _journal(String message) {
  if (kDebugMode) debugPrint('[HomePage] $message');
}

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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  String? _prenom;
  // ⚠️ Aucune source actuelle (pas de reverse-geocoding) : HomeScreen
  // affiche « Ma position » quand c'est null.
  final String? _quartier = null;
  int _soldeFcfa = 0;
  bool _chargementConducteurs = true;
  bool _requeteConducteursEnCours = false;
  List<ConducteurProche> _conducteurs = const [];
  List<SuggestionDestination> _suggestions = const [];
  LatLng? _positionClient;
  CourseActive? _courseActive;
  Timer? _minuteurConducteurs;
  // Vérification d'identité (facultative) : statut lu dans mon-profil/, et
  // statut pour lequel le client a fermé l'invitation (elle revient si le
  // statut change, par exemple après un refus).
  StatutIdentite? _statutIdentite;
  String? _invitationMasqueePour;

  final Map<String, _EntreeCacheDuree> _cacheDurees = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ConfigApp.paiementActif.addListener(_surChangementPaiement);
    _chargerProfil();
    _chargerSolde();
    _chargerCourseActive();
    _initialiserPositionPuisDependances();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ConfigApp.paiementActif.removeListener(_surChangementPaiement);
    _arreterRafraichissement();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState etat) {
    switch (etat) {
      case AppLifecycleState.resumed:
        _chargerConducteursProches(silencieux: true);
        _chargerCourseActive();
        _demarrerRafraichissement();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _arreterRafraichissement();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Chauffeurs proches seulement : la course active n'est PAS relue ici
  /// (mes-demandes/ renvoie tout l'historique, trop lourd toutes les 20 s).
  /// Elle l'est à l'ouverture, au retour au premier plan et au retour du suivi.
  void _demarrerRafraichissement() {
    _minuteurConducteurs?.cancel();
    _minuteurConducteurs = Timer.periodic(
      _intervalleConducteurs,
      (_) => _chargerConducteursProches(silencieux: true),
    );
  }

  void _arreterRafraichissement() {
    _minuteurConducteurs?.cancel();
    _minuteurConducteurs = null;
  }

  void _surChangementPaiement() {
    if (ConfigApp.paiementActif.value) _chargerSolde();
  }

  /// Cherche une course non terminée pour proposer d'en reprendre le suivi.
  /// Filtrage par exclusion des statuts terminés (voir _statutsTermines),
  /// on écarte les courses planifiées encore futures et les demandes trop
  /// vieilles, et on garde la plus récente. Échec silencieux (confort).
  Future<void> _chargerCourseActive() async {
    try {
      final demandes = await ApiService.mesDemandesClient();
      if (!mounted) return;
      final maintenant = DateTime.now();
      CourseActive? active;
      DateTime meilleureDate = DateTime(2000);
      for (final d in demandes) {
        if (d is! Map) continue;
        final statut = d['statut']?.toString().toLowerCase() ?? '';
        if (statut.isEmpty || _statutsTermines.contains(statut)) continue;

        // Course planifiée dont l'heure n'est pas encore venue : pas "en cours".
        final planif = DateTime.tryParse(d['date_heure_planifiee']?.toString() ?? '');
        if (planif != null && planif.isAfter(maintenant)) continue;

        final creeLe = DateTime.tryParse(d['cree_le']?.toString() ?? '');
        if (creeLe != null && maintenant.difference(creeLe) > _ageMaxCourseActive) {
          continue;
        }

        final idBrut = d['id'];
        final id = idBrut is int ? idBrut : int.tryParse(idBrut.toString());
        if (id == null) continue;

        // Jamais de valeur inventée : sans destination ni type de transport
        // réels, le suivi s'ouvrirait sur des données fausses.
        final destination = d['destination']?.toString().trim() ?? '';
        final typeTransport = d['type_transport']?.toString().trim() ?? '';
        if (destination.isEmpty || typeTransport.isEmpty) continue;

        final ref = creeLe ?? DateTime(2000);
        if (active == null || ref.isAfter(meilleureDate)) {
          meilleureDate = ref;
          active = CourseActive(
            id: id,
            destination: destination,
            typeTransport: typeTransport,
            statut: statut,
          );
        }
      }
      if (!mounted) return;
      setState(() => _courseActive = active);
    } catch (e) {
      _journal('Erreur chargement course active : $e');
    }
  }

  Future<void> _reprendreCourse(CourseActive course) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SuiviCoursePage(
          demandeId: course.id,
          destination: course.destination,
          typeTransport: course.typeTransport,
        ),
      ),
    );
    // Au retour du suivi (course terminée/annulée, ou toujours en cours) on
    // réévalue pour masquer ou garder le bandeau.
    if (mounted) _chargerCourseActive();
  }

  // ─── Chargement des données ───

  Future<void> _chargerProfil() async {
    try {
      final profil = await ApiService.monProfil();
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final prenom = (profil['first_name'] as String?)?.trim();
      setState(() {
        _prenom = (prenom == null || prenom.isEmpty) ? null : prenom;
        _statutIdentite = statutIdentiteDepuis(profil['verification_identite']);
        _invitationMasqueePour = prefs.getString(_cleInvitationIdentiteMasquee);
      });
    } catch (e) {
      _journal('Erreur chargement profil : $e');
    }
  }

  /// Seulement sans pièce ou après un refus, et pas si le client l'a fermée
  /// pour ce même statut. Statut inconnu (ancien serveur) : rien.
  InvitationIdentite? get _invitationIdentite {
    final invitation = switch (_statutIdentite) {
      StatutIdentite.nonSoumis => InvitationIdentite.aVerifier,
      StatutIdentite.refuse => InvitationIdentite.aRenvoyer,
      _ => null,
    };
    return invitation == null || _invitationMasqueePour == _statutIdentite!.name ? null : invitation;
  }

  Future<void> _masquerInvitationIdentite() async {
    final statut = _statutIdentite;
    if (statut == null) return;
    setState(() => _invitationMasqueePour = statut.name);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cleInvitationIdentiteMasquee, statut.name);
    } catch (e) {
      _journal('Mémoire de l’invitation impossible : $e');
    }
  }

  Future<void> _ouvrirVerificationIdentite() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PageVerificationIdentite()),
    );
    if (mounted) _chargerProfil();
  }

  Future<void> _chargerSolde() async {
    // Mode gratuit : aucun solde affiché, donc aucune requête.
    if (!ConfigApp.paiementActif.value) return;
    try {
      final solde = await ApiService.monSolde();
      if (!mounted) return;
      setState(() => _soldeFcfa = solde);
    } catch (e) {
      _journal('Erreur chargement solde : $e');
    }
  }

  /// Position d'abord (nécessaire aux chauffeurs proches ET aux durées OSRM),
  /// puis tout ce qui en dépend, puis le rafraîchissement périodique.
  Future<void> _initialiserPositionPuisDependances() async {
    await _obtenirPosition();
    await Future.wait([
      _chargerConducteursProches(),
      _chargerSuggestions(),
    ]);
    if (mounted) _demarrerRafraichissement();
  }

  Future<void> _obtenirPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() => _positionClient = LatLng(position.latitude, position.longitude));
    } catch (e) {
      _journal('Erreur position GPS : $e');
    }
  }

  /// ⚠️ Le backend n'expose pas de « type » d'adresse, seulement un libellé
  /// libre : déduction cosmétique (choix de l'icône) uniquement.
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

      final entrees = brut.whereType<Map>().toList(growable: false);
      // Durées OSRM en parallèle (avant : une à une, lent avec 5 favoris).
      final suggestions = await Future.wait(entrees.map((map) async {
        final id = map['id']?.toString() ?? '';
        final lat = (map['latitude'] as num?)?.toDouble();
        final lng = (map['longitude'] as num?)?.toDouble();
        final libelle = (map['libelle'] ?? '').toString().trim();
        return SuggestionDestination(
          id: id,
          libelle: libelle,
          type: _deduireType(libelle),
          dureeMinutes: await _dureeAvecCache(id, lat, lng),
        );
      }));
      if (!mounted) return;
      setState(() => _suggestions = [
            for (final s in suggestions)
              if (s.id.isNotEmpty && s.libelle.isNotEmpty) s,
          ]);
    } catch (e) {
      _journal('Erreur chargement suggestions : $e');
    }
  }

  Future<int?> _dureeAvecCache(String id, double? lat, double? lng) async {
    final position = _positionClient;
    if (lat == null || lng == null || position == null) return null;

    final entree = _cacheDurees[id];
    if (entree != null && !entree.expiree) return entree.dureeMinutes;

    try {
      final duree = await RoutingService.dureeMinutesVers(
        depart: position,
        arrivee: LatLng(lat, lng),
      );
      _cacheDurees[id] = _EntreeCacheDuree(duree, DateTime.now());
      return duree;
    } catch (e) {
      _journal('Erreur durée OSRM : $e');
      return null; // la puce s'affiche sans durée
    }
  }

  static String? _urlHttpsOuNull(Object? valeur) {
    if (valeur is! String) return null;
    final uri = Uri.tryParse(valeur);
    return (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) ? valeur : null;
  }

  /// null si l'entrée est inexploitable (pas de coordonnées valides).
  ConducteurProche? _conducteurDepuisJson(Object? brut) {
    if (brut is! Map) return null;
    final id = brut['id']?.toString();
    final lat = (brut['lat'] as num?)?.toDouble();
    final lng = (brut['lng'] as num?)?.toDouble();
    if (id == null || lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;

    final noteBrute = brut['note'];
    return ConducteurProche(
      id: id,
      nomCourt: (brut['nom_court'] ?? '').toString(),
      position: LatLng(lat, lng),
      urlPhoto: _urlHttpsOuNull(brut['photo_profil']),
      note: noteBrute == null ? null : double.tryParse(noteBrute.toString()),
      modeleVehicule: brut['vehicule'] as String?,
      minutesAvant: (brut['temps_minutes'] as num?)?.toInt(),
      estMoto: brut['type_transport'] == CodesTransport.moto,
    );
  }

  /// [silencieux] : pas d'indicateur « Recherche… » (rafraîchissement auto),
  /// pour éviter que la pastille clignote toutes les 20 s.
  Future<void> _chargerConducteursProches({bool silencieux = false}) async {
    if (_requeteConducteursEnCours) return;
    final position = _positionClient;
    if (position == null) {
      if (mounted && _chargementConducteurs) {
        setState(() => _chargementConducteurs = false);
      }
      return;
    }

    _requeteConducteursEnCours = true;
    if (!silencieux && mounted) setState(() => _chargementConducteurs = true);
    try {
      final brut = await ApiService.conducteursProches(
        lat: position.latitude,
        lng: position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _conducteurs = [
          for (final c in brut)
            if (_conducteurDepuisJson(c) case final ConducteurProche conducteur) conducteur,
        ];
        _chargementConducteurs = false;
      });
    } catch (e) {
      _journal('Erreur chargement conducteurs proches : $e');
      if (mounted) setState(() => _chargementConducteurs = false);
    } finally {
      _requeteConducteursEnCours = false;
    }
  }

  /// Les tarifs-min n'ont pas encore d'endpoint : seuls les chauffeurs
  /// sont rechargés. À compléter quand ApiService.tarifsMinServices existera.
  Future<void> _actualiser() async {
    await _chargerConducteursProches();
  }

  Future<void> _recentrer() async {
    await _obtenirPosition();
    await _chargerConducteursProches(silencieux: true);
  }

  // ─── Navigation ───

  Future<void> _ouvrirRecherche({String? typePreselectionne}) async {
    final resultat = await Navigator.push<DestinationChoisie>(
      context,
      MaterialPageRoute(builder: (_) => const EcranRecherche()),
    );
    if (resultat == null || !mounted) return;
    _ouvrirDemandeInstantanee(
      resultat.nom,
      typePreselectionne: typePreselectionne,
      destinationLat: resultat.lat,
      destinationLng: resultat.lng,
    );
  }

  void _ouvrirDemandeInstantanee(
    String destination, {
    String? typePreselectionne,
    double? destinationLat,
    double? destinationLng,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EcranDemandeInstantanee(
          destination: destination,
          typePreselectionne: typePreselectionne,
          destinationLat: destinationLat,
          destinationLng: destinationLng,
        ),
      ),
    );
  }

  Future<void> _ajouterAdresse() async {
    final saisie = await showDialog<({String libelle, String adresse, double? lat, double? lng})>(
      context: context,
      builder: (_) => const _DialogueNouvelleAdresse(),
    );
    if (saisie == null || !mounted) return;

    try {
      await ApiService.enregistrerAdresseFavorite(
        libelle: saisie.libelle,
        adresse: saisie.adresse,
        latitude: saisie.lat,
        longitude: saisie.lng,
      );
      await _chargerSuggestions();
    } catch (e) {
      _journal('Erreur enregistrement adresse favorite : $e');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("Impossible d'enregistrer l'adresse. Réessayez.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConfigApp.paiementActif,
      builder: (context, paiementActif, _) => _ecran(context, paiementActif),
    );
  }

  Widget _ecran(BuildContext context, bool paiementActif) {
    final nuit = Theme.of(context).brightness == Brightness.dark;
    return HomeScreen(
      paiementActif: paiementActif,
      // ⚠️ Seule ligne non vérifiée : reprendre EXACTEMENT les paramètres
      // utilisés pour FondCarteTaama sur les autres écrans (taama_map.dart).
      coucheFond: FondCarteTaama(nuit: nuit),
      nuit: nuit,
      prenom: _prenom,
      quartier: _quartier,
      // ⚠️ Aucune source actuelle : initiale du prénom affichée.
      urlPhotoProfil: null,
      soldeFcfa: _soldeFcfa,
      // ⚠️ Endpoint tarifs-min pas encore créé : tuiles sans prix, jamais
      // de prix inventé.
      services: const [],
      suggestions: _suggestions,
      conducteursProches: _conducteurs,
      positionClient: _positionClient,
      chargementConducteurs: _chargementConducteurs,
      courseActive: _courseActive,
      onReprendreCourse: _reprendreCourse,
      invitationIdentite: _invitationIdentite,
      onVerifierIdentite: _ouvrirVerificationIdentite,
      onMasquerInvitationIdentite: _masquerInvitationIdentite,
      // ⚠️ Endpoint dernière course pas encore créé : carte masquée.
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
      // Inaccessible en mode gratuit : HomeScreen n'affiche le solde que si
      // paiementActif.
      onPortefeuille: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EcranPortefeuille(estChauffeur: false)),
      ),
      onProfil: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EcranProfil()),
      ),
      onRecentrerCarte: _recentrer,
      onRefaireCourse: null,
      onDicterDestination: null,
      onActualiser: _actualiser,
    );
  }
}

/// Possède ses propres contrôleurs : ils sont libérés avec le dialogue
/// (les libérer juste après showDialog plante pendant l'animation de sortie).
class _DialogueNouvelleAdresse extends StatefulWidget {
  const _DialogueNouvelleAdresse();

  @override
  State<_DialogueNouvelleAdresse> createState() => _DialogueNouvelleAdresseState();
}

class _DialogueNouvelleAdresseState extends State<_DialogueNouvelleAdresse> {
  final _formulaire = GlobalKey<FormState>();
  final _libelle = TextEditingController();
  final _adresse = TextEditingController();
  LieuTrouve? _lieu;

  @override
  void dispose() {
    _libelle.dispose();
    _adresse.dispose();
    super.dispose();
  }

  String? _obligatoire(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ obligatoire' : null;

  void _valider() {
    if (!(_formulaire.currentState?.validate() ?? false)) return;
    final adresse = _adresse.text.trim();
    final lieu = _lieu ?? lieuExact(adresse);
    Navigator.pop(context, (
      libelle: _libelle.text.trim(),
      adresse: adresse,
      lat: lieu?.lat,
      lng: lieu?.lng,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Nouvelle adresse'),
      content: Form(
        key: _formulaire,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _libelle,
              maxLength: _longueurMaxLibelle,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Libellé (ex. Maison)'),
              validator: _obligatoire,
            ),
            const SizedBox(height: 8),
            ChampAdresseLieu(
              controleur: _adresse,
              longueurMax: _longueurMaxAdresse,
              onLieu: (lieu) => _lieu = lieu,
              onValider: _valider,
              decoration: const InputDecoration(labelText: 'Adresse'),
              validator: _obligatoire,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valider,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
