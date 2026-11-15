import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'chauffeur_proche.dart';
import 'chauffeurs_proches_repository.dart';

/// Logique de l'écran, sans dépendance à l'UI : rafraîchissement périodique
/// avec repli progressif, filtre, sélection et détection des positions
/// périmées (le choix est alors bloqué : fail-closed).
class RechercheChauffeurController extends ChangeNotifier {
  RechercheChauffeurController({
    required ChauffeursProchesRepository repository,
    required GeoPoint position,
    this.rayonDemande = 3000,
    this.intervalle = const Duration(seconds: 10),
    this.delaiObsolescence = const Duration(seconds: 30),
    DateTime Function()? horloge,
  })  : assert(rayonDemande > 0),
        _repository = repository,
        _position = position,
        _centre = position,
        _rayonM = rayonDemande,
        _horloge = horloge ?? DateTime.now;

  static const _maxChauffeurs = 30;

  final int rayonDemande;
  final Duration intervalle;
  final Duration delaiObsolescence;

  final ChauffeursProchesRepository _repository;
  final DateTime Function() _horloge;

  GeoPoint _position;
  GeoPoint _centre;
  int _rayonM;
  List<ChauffeurProche> _tous = const [];
  TypeVehicule? _filtre;
  String? _idSelectionne;
  DateTime? _derniereMaj;
  bool _chargementInitial = true;
  String? _erreur;
  int _echecsConsecutifs = 0;
  bool _enCours = false;
  bool _actif = false;
  bool _detruit = false;
  Timer? _minuteur;
  Timer? _minuteurObsolescence;

  /// Centre des positions affichées : celui de la dernière recherche réussie.
  GeoPoint get centre => _centre;
  int get rayonM => _rayonM;
  TypeVehicule? get filtre => _filtre;
  bool get chargementInitial => _chargementInitial;
  String? get erreur => _erreur;
  List<ChauffeurProche> get tous => _tous;

  List<ChauffeurProche> get chauffeursFiltres {
    final filtre = _filtre;
    if (filtre == null) return _tous;
    return _tous
        .where((c) => c.typeVehicule == filtre)
        .toList(growable: false);
  }

  int nombre([TypeVehicule? type]) => type == null
      ? _tous.length
      : _tous.where((c) => c.typeVehicule == type).length;

  /// Chauffeur sélectionné ; par défaut le plus proche de la liste filtrée.
  ChauffeurProche? get selectionne {
    final liste = chauffeursFiltres;
    if (liste.isEmpty) return null;
    for (final c in liste) {
      if (c.id == _idSelectionne) return c;
    }
    return liste.first;
  }

  bool get estObsolete {
    final maj = _derniereMaj;
    return maj == null || _horloge().difference(maj) > delaiObsolescence;
  }

  /// Active le rafraîchissement et lance une recherche immédiate.
  /// Sert aussi de « Réessayer ».
  void demarrer() {
    if (_detruit) return;
    _actif = true;
    unawaited(_rafraichir());
  }

  void suspendre() {
    _actif = false;
    _minuteur?.cancel();
    _minuteur = null;
  }

  Future<void> rafraichir() => _rafraichir();

  Future<void> changerPosition(GeoPoint position) {
    if (_detruit || !position.estValide) return Future<void>.value();
    _position = position;
    return _rafraichir();
  }

  void choisirFiltre(TypeVehicule? type) {
    if (_detruit || type == _filtre) return;
    _filtre = type;
    _idSelectionne = selectionne?.id;
    notifyListeners();
  }

  void selectionner(ChauffeurProche chauffeur) {
    if (_detruit || chauffeur.id == _idSelectionne) return;
    _idSelectionne = chauffeur.id;
    notifyListeners();
  }

  Future<void> _rafraichir() async {
    if (_enCours || _detruit) return;
    _enCours = true;
    _minuteur?.cancel();
    _minuteur = null;
    final positionDemandee = _position;

    try {
      final resultat = await _repository.rechercher(
        position: positionDemandee,
        rayonM: rayonDemande,
      );
      if (_detruit) return;
      final tries = [...resultat.chauffeurs]..sort(_parProximite);
      _tous = List.unmodifiable(tries.take(_maxChauffeurs));
      _centre = positionDemandee;
      _rayonM = resultat.rayonM;
      _derniereMaj = _horloge();
      _erreur = null;
      _echecsConsecutifs = 0;
      _armerObsolescence();
    } on RechercheChauffeursException catch (e) {
      if (_detruit) return;
      _erreur = e.message;
      _echecsConsecutifs++;
      if (!e.reessayable) _actif = false;
    } catch (e, pile) {
      if (_detruit) return;
      if (kDebugMode) debugPrint('Recherche chauffeurs : $e\n$pile');
      _erreur = 'Impossible de charger les chauffeurs pour le moment.';
      _echecsConsecutifs++;
    } finally {
      _enCours = false;
    }

    if (_detruit) return;
    _chargementInitial = false;
    notifyListeners();
    // Position changée pendant la requête : relancer tout de suite.
    _planifier(immediat: _position != positionDemandee);
  }

  void _planifier({bool immediat = false}) {
    _minuteur?.cancel();
    _minuteur = null;
    if (!_actif || _detruit) return;
    // Repli progressif après échec : 10 s, 20 s, 40 s, puis 60 s maximum.
    final facteur = _echecsConsecutifs == 0
        ? 1
        : math.min(1 << math.min(_echecsConsecutifs, 3), 6);
    final delai = immediat ? Duration.zero : intervalle * facteur;
    _minuteur = Timer(delai, () => unawaited(_rafraichir()));
  }

  /// Notifie l'UI pile au moment où les positions deviennent périmées,
  /// sans attendre la prochaine réponse réseau.
  void _armerObsolescence() {
    _minuteurObsolescence?.cancel();
    _minuteurObsolescence = Timer(
      delaiObsolescence + const Duration(milliseconds: 50),
      () {
        if (!_detruit) notifyListeners();
      },
    );
  }

  static int _parProximite(ChauffeurProche a, ChauffeurProche b) {
    final parEta = a.etaMin.compareTo(b.etaMin);
    return parEta != 0 ? parEta : a.distanceM.compareTo(b.distanceM);
  }

  @override
  void dispose() {
    _detruit = true;
    _actif = false;
    _minuteur?.cancel();
    _minuteurObsolescence?.cancel();
    super.dispose();
  }
}
