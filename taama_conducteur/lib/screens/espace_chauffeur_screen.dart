// DESIGN_V3_FINAL
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../services/demande_entrante_navigator.dart';
import '../services/location_service.dart';
import '../theme/couleurs_taama.dart';
import 'connexion_screen.dart';
import 'profil_chauffeur_screen.dart';
import 'portefeuille_screen.dart';
import 'chat_screen.dart';
import 'mes_conversations_screen.dart';
import 'verification_conducteur_screen.dart';
import 'navigation_screen.dart';
import 'avis_app_screen.dart';
import 'courier_livreur_screen.dart';
import '../widgets/widget_annulation.dart';

class EcranEspaceChauffeur extends StatefulWidget {
  const EcranEspaceChauffeur({super.key});

  @override
  State<EcranEspaceChauffeur> createState() => _EcranEspaceChauffeurState();
}

class _EcranEspaceChauffeurState extends State<EcranEspaceChauffeur> {
  Map<String, dynamic>? _profil;
  List<dynamic> _demandesAssignees = [];
  List<dynamic> _livraisonsCourier = [];
  int? _solde;
  Timer? _timerPolling;
  bool _chargementInitial = true;
  int? _enTraitement;

  // Une position GPS est envoyée en continu pour chaque demande "en route"
  final Map<int, LocationService> _servicesLocalisation = {};

  // Position GPS envoyée en continu tant que le conducteur est "disponible",
  // même sans course en cours (canal général "disponibilite").
  final LocationService _serviceLocalisationGenerale = LocationService();

  @override
  void initState() {
    super.initState();
    _chargerProfil();
    _chargerSolde();
    _rafraichirTout();
    _timerPolling = Timer.periodic(const Duration(seconds: 5), (_) => _rafraichirTout());
  }

  @override
  void dispose() {
    _timerPolling?.cancel();
    for (final service in _servicesLocalisation.values) {
      service.arreter();
    }
    _serviceLocalisationGenerale.arreterSuiviPositionEnLigne();
    super.dispose();
  }

  /// Démarre l'envoi de la position GPS pour chaque demande qui vient de
  /// passer "en route", et l'arrête pour celles qui ne le sont plus
  /// (terminées, annulées, ou disparues de la liste des demandes assignées).
  ///
  /// Appelée à CHAQUE tick de _rafraichirTout, quoi qu'il arrive par
  /// ailleurs (voir _rafraichirTout) — try/catch défensif avec un tag de log
  /// distinct : une régression ici (ex. cast id invalide) ne doit jamais
  /// passer inaperçue, mais ne doit pas non plus empêcher le prochain tick.
  void _synchroniserSuiviPosition() {
    try {
      final idsEnRoute = _demandesAssignees
          .where((d) => d['statut'] == 'en_route')
          .map((d) => d['id'] as int)
          .toSet();

      for (final id in idsEnRoute) {
        if (!_servicesLocalisation.containsKey(id)) {
          final service = LocationService();
          service.demarrerEnvoiPosition('$id');
          _servicesLocalisation[id] = service;
        }
      }

      final idsATerminer = _servicesLocalisation.keys.where((id) => !idsEnRoute.contains(id)).toList();
      for (final id in idsATerminer) {
        _servicesLocalisation.remove(id)?.arreter();
      }
    } catch (e) {
      debugPrint('[SuiviPosition] Erreur synchronisation : $e');
    }
  }

  Future<void> _chargerProfil() async {
    try {
      final profil = await ApiService.monProfilChauffeur();
      if (!mounted) return;
      setState(() => _profil = profil);
      // Si le conducteur était déjà en ligne (ex: relance de l'app), on
      // reprend le suivi GPS.
      if (profil['disponible'] == true) {
        _serviceLocalisationGenerale.demarrerSuiviPositionEnLigne();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ce compte n\'est pas encore lié à un profil conducteur.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _chargementInitial = false);
    }
  }

  Future<void> _chargerSolde() async {
    try {
      final solde = await ApiService.monSolde();
      if (!mounted) return;
      setState(() => _solde = solde);
    } catch (e) {
      debugPrint('Erreur chargement solde : $e');
    }
  }

  /// Rafraîchit chaque source de façon INDÉPENDANTE : l'échec d'une (ex. un
  /// endpoint retiré, une erreur réseau ponctuelle) ne doit jamais empêcher
  /// les autres de s'exécuter. En particulier, le suivi GPS et la
  /// resynchronisation de la disponibilité sont critiques (un chauffeur qui
  /// arrête de pousser sa position ou de resynchroniser sa dispo devient
  /// invisible/incohérent sans que rien ne le signale) : ils tournent à
  /// CHAQUE tick, quoi qu'il arrive sur les autres sources ci-dessous.
  Future<void> _rafraichirTout() async {
    await Future.wait([
      _rafraichirDemandesAssignees(),
      _rafraichirLivraisonsCourier(),
    ]);

    // Dépend de _demandesAssignees, donc appelé après son rafraîchissement —
    // mais _rafraichirDemandesAssignees() ne relance jamais d'exception (try/
    // catch interne), donc ce point est toujours atteint.
    _synchroniserSuiviPosition();

    // Le serveur peut désormais faire basculer `disponible` tout seul
    // (acceptation/fin de course) — je resynchronise le toggle affiché
    // sans jamais toucher au suivi GPS (celui-ci ne dépend que de l'action
    // explicite du conducteur sur le toggle, pas de sa disponibilité).
    await _resynchroniserDisponibilite();
  }

  Future<void> _rafraichirDemandesAssignees() async {
    try {
      final demandes = await ApiService.mesDemandesAssignees();
      if (!mounted) return;
      _detecterNouvelleDemande(demandes);
      setState(() => _demandesAssignees = demandes);
    } catch (e) {
      debugPrint('[DemandesAssignees] Erreur rafraîchissement : $e');
    }
  }

  /// Filet de secours fiable pour ouvrir l'écran de demande entrante : dès
  /// qu'une demande 'chauffeur_trouve' apparaît qui n'était pas connue au
  /// tick précédent, on l'affiche. Complète le déclenchement FCM (qui ne
  /// couvre que le tap sur la notification), pas besoin que l'app soit au
  /// premier plan sur CET écran précis — ce polling tourne dès que
  /// l'espace chauffeur est ouvert.
  void _detecterNouvelleDemande(List<dynamic> nouvellesDemandes) {
    final idsDejaConnus = _demandesAssignees.map((d) => d['id']).toSet();
    for (final demande in nouvellesDemandes) {
      final id = demande['id'];
      if (demande['statut'] == 'chauffeur_trouve' && !idsDejaConnus.contains(id)) {
        DemandeEntranteNavigator.afficherSiNecessaire(
          id as int,
          demandeInitiale: demande as Map<String, dynamic>,
        );
      }
    }
  }

  Future<void> _rafraichirLivraisonsCourier() async {
    try {
      final livraisons = await ApiService.mesLivraisonsCourier();
      if (!mounted) return;
      setState(() => _livraisonsCourier = livraisons);
    } catch (e) {
      debugPrint('[LivraisonsCourier] Erreur rafraîchissement : $e');
    }
  }

  Future<void> _resynchroniserDisponibilite() async {
    try {
      final profil = await ApiService.monProfilChauffeur();
      if (!mounted) return;
      setState(() => _profil?['disponible'] = profil['disponible']);

      // Garde-fou : si le serveur dit "disponible" mais que le suivi GPS
      // général n'est plus actif (stream mort en silence, exception
      // avalée...), on le relance. Un chauffeur "disponible mais invisible"
      // est pire qu'un chauffeur clairement hors ligne.
      if (profil['disponible'] == true && !_serviceLocalisationGenerale.enLigne) {
        debugPrint('[Disponibilite] Suivi GPS inactif alors que disponible=true — relance');
        await _serviceLocalisationGenerale.demarrerSuiviPositionEnLigne();
      }
    } catch (e) {
      debugPrint('[Disponibilite] Erreur resynchronisation : $e');
    }
  }

  Future<void> _basculerDisponibilite() async {
    try {
      final nouvelleDisponibilite = await ApiService.changerDisponibilite();
      if (!mounted) return;
      setState(() => _profil?['disponible'] = nouvelleDisponibilite);

      if (nouvelleDisponibilite) {
        // Conducteur passe en ligne → démarre le suivi GPS
        await _serviceLocalisationGenerale.demarrerSuiviPositionEnLigne();
        debugPrint('[GPS] Suivi de position démarré');
      } else {
        // Conducteur passe hors ligne → arrête le suivi GPS
        await _serviceLocalisationGenerale.arreterSuiviPositionEnLigne();
        debugPrint('[GPS] Suivi de position arrêté');
      }
    } catch (e) {
      debugPrint('Erreur changement disponibilité : $e');
    }
  }

  Future<void> _accepterDemande(int id) async {
    setState(() => _enTraitement = id);
    try {
      await ApiService.accepterDemande(id);
      await _rafraichirTout();
    } finally {
      if (mounted) setState(() => _enTraitement = null);
    }
  }

  Future<void> _refuserDemande(int id) async {
    setState(() => _enTraitement = id);
    try {
      await ApiService.refuserDemande(id);
      await _rafraichirTout();
    } finally {
      if (mounted) setState(() => _enTraitement = null);
    }
  }

  Future<void> _annulerCourse(int demandeId, DateTime dateCreation) async {
    final resultat = await afficherDialogueAnnulation(
      context,
      dateCreation: dateCreation,
      estChauffeur: true,
    );
    if (resultat == null) return;

    try {
      final reponse = await ApiService.annulerDemandeChaufeur(
        demandeId,
        motif: resultat['motif'] as String,
      );

      final penalite = reponse['penalite'] as int? ?? 0;
      final avertissement = reponse['avertissement'] as String?;

      if (!mounted) return;

      if (avertissement != null) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text('Avertissement'),
              ],
            ),
            content: Text(avertissement),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Compris'),
              ),
            ],
          ),
        );
      } else if (penalite > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Course annulée. Pénalité : $penalite FCFA'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      _rafraichirTout();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  void _deconnexion() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const EcranConnexion()),
      (route) => false,
    );
  }

  void _ouvrirChat({required String roomName, required String titre}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => EcranChat(roomName: roomName, titreConversation: titre)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disponible = _profil?['disponible'] as bool? ?? false;

    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      appBar: AppBar(
        title: const Text('Taama Conducteur', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: CouleursTaama.indigo,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble, color: Colors.white),
            tooltip: 'Messages',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MesConversationsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet, color: Colors.white),
            tooltip: 'Mon portefeuille',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EcranPortefeuille(estChauffeur: true)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            tooltip: 'Mon profil',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EcranProfilChauffeur()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.star_rate, color: Colors.white),
            tooltip: 'Donner mon avis',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EcranAvisApp()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Déconnexion',
            onPressed: _deconnexion,
          ),
        ],
      ),
      body: _chargementInitial
          ? const Center(child: CircularProgressIndicator(color: CouleursTaama.terreCuite))
          : RefreshIndicator(
              color: CouleursTaama.terreCuite,
              onRefresh: () async {
                await _chargerProfil();
                await _chargerSolde();
                await _rafraichirTout();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  // 1. Carte de profil
                  if (_profil != null)
                    _CarteProfil(
                      profil: _profil!,
                      disponible: disponible,
                      onToggle: _basculerDisponibilite,
                    ),
                  const SizedBox(height: 20),

                  // 2. Stats rapides
                  Row(
                    children: [
                      Expanded(
                        child: _CarteStat(
                          icone: Icons.directions_car,
                          couleur: CouleursTaama.terreCuite,
                          valeur: '${_demandesAssignees.length}',
                          libelle: 'Courses du jour',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CarteStat(
                          icone: Icons.account_balance_wallet,
                          couleur: CouleursTaama.indigo,
                          valeur: _solde != null ? '$_solde' : '...',
                          libelle: 'Solde (FCFA)',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CarteStat(
                          icone: Icons.star,
                          couleur: CouleursTaama.or,
                          valeur: _profil != null ? (_profil!['note'] as num?)?.toStringAsFixed(1) ?? '—' : '-',
                          libelle: 'Note',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // 3. Demandes en cours
                  if (_demandesAssignees.isNotEmpty) ...[
                    const Text(
                      'Demandes en cours',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: CouleursTaama.indigo),
                    ),
                    const SizedBox(height: 12),
                    ..._demandesAssignees.map((demande) {
                      final enAttente = demande['statut'] == 'chauffeur_trouve';
                      final demandeId = demande['id'] as int;
                      final dateCreation = DateTime.tryParse(demande['cree_le']?.toString() ?? '') ?? DateTime.now();
                      return _CarteDemande(
                        demande: demande,
                        enAttente: enAttente,
                        enTraitement: _enTraitement == demande['id'],
                        onRefuser: () => _refuserDemande(demande['id'] as int),
                        onAccepter: () => _accepterDemande(demande['id'] as int),
                        onChat: () => _ouvrirChat(
                          roomName: 'demande_${demande['id']}',
                          titre: 'Client - ${demande['destination']}',
                        ),
                        onAnnuler: () => _annulerCourse(demandeId, dateCreation),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],

                  // 3.5 Livraisons Courier en cours
                  if (_livraisonsCourier.isNotEmpty) ...[
                    const Text(
                      '📦 Livraisons en cours',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: CouleursTaama.indigo),
                    ),
                    const SizedBox(height: 12),
                    ..._livraisonsCourier.map((livraison) {
                      return _CarteLivraisonCourier(
                        livraison: livraison,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EcranCourierLivreur(
                                livraison: livraison as Map<String, dynamic>,
                              ),
                            ),
                          );
                          if (mounted) await _rafraichirTout();
                        },
                      );
                    }),
                    const SizedBox(height: 24),
                  ],

                ],
              ),
            ),
    );
  }
}

/// Carte de profil du conducteur : avatar avec initiales, nom, véhicule,
/// switch de disponibilité et badge de note moyenne.
class _CarteProfil extends StatelessWidget {
  final Map<String, dynamic> profil;
  final bool disponible;
  final VoidCallback onToggle;

  const _CarteProfil({required this.profil, required this.disponible, required this.onToggle});

  String get _initiales {
    final parties = (profil['nom']?.toString() ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parties.isEmpty) return '?';
    if (parties.length == 1) {
      return parties[0].substring(0, parties[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parties[0][0] + parties[1][0]).toUpperCase();
  }

  Widget _badgeVerification(BuildContext context) {
    final verifie = profil['verifie'] as bool? ?? false;
    final statut = profil['statut_verification']?.toString() ?? 'non_soumis';

    late Color couleur;
    late IconData icone;
    late String libelle;

    if (verifie) {
      couleur = Colors.green;
      icone = Icons.check_circle;
      libelle = 'Vérifié';
    } else if (statut == 'en_attente') {
      couleur = CouleursTaama.or;
      icone = Icons.hourglass_top;
      libelle = 'En attente';
    } else {
      couleur = Colors.red;
      icone = Icons.cancel;
      libelle = 'Non vérifié';
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const EcranVerificationConducteur()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: couleur, size: 14),
            const SizedBox(width: 4),
            Text(libelle, style: TextStyle(color: couleur, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final note = (profil['note'] as num?)?.toStringAsFixed(1) ?? '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: CouleursTaama.indigo,
            radius: 26,
            child: Text(
              _initiales,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profil['nom']?.toString() ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  '${profil['vehicule']} • ${profil['plaque']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: CouleursTaama.or.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: CouleursTaama.or, size: 14),
                          const SizedBox(width: 4),
                          Text(note, style: const TextStyle(color: CouleursTaama.or, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                    _badgeVerification(context),
                  ],
                ),
              ],
            ),
          ),
          Switch(
            value: disponible,
            activeThumbColor: Colors.amber,
            inactiveThumbColor: Colors.grey.shade400,
            inactiveTrackColor: Colors.grey.shade300,
            onChanged: (_) => onToggle(),
          ),
        ],
      ),
    );
  }
}

/// Une des 3 cartes de statistiques rapides (courses du jour, solde, note).
class _CarteStat extends StatelessWidget {
  final IconData icone;
  final Color couleur;
  final String valeur;
  final String libelle;

  const _CarteStat({required this.icone, required this.couleur, required this.valeur, required this.libelle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icone, color: couleur, size: 22),
          const SizedBox(height: 6),
          Text(valeur, style: TextStyle(color: couleur, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 2),
          Text(
            libelle,
            textAlign: TextAlign.center,
            style: TextStyle(color: couleur, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Une carte de demande instantanée assignée au conducteur.
class _CarteDemande extends StatelessWidget {
  final dynamic demande;
  final bool enAttente;
  final bool enTraitement;
  final VoidCallback onRefuser;
  final VoidCallback onAccepter;
  final VoidCallback onChat;
  final VoidCallback onAnnuler;

  const _CarteDemande({
    required this.demande,
    required this.enAttente,
    required this.enTraitement,
    required this.onRefuser,
    required this.onAccepter,
    required this.onChat,
    required this.onAnnuler,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: const Border(left: BorderSide(color: CouleursTaama.terreCuite, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(demande['destination']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text('${demande['type_transport']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text(
            '${demande['prix_estime']} FCFA',
            style: const TextStyle(color: CouleursTaama.terreCuite, fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 12),
          if (enAttente)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: enTraitement ? null : onRefuser,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Refuser'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: enTraitement ? null : onAccepter,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: enTraitement
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Accepter'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onChat,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CouleursTaama.indigo,
                      side: const BorderSide(color: CouleursTaama.indigo),
                    ),
                    child: const Icon(Icons.chat_bubble_outline, size: 18),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                const Expanded(
                  child: Text('En route', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
                OutlinedButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Chat'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CouleursTaama.indigo,
                    side: const BorderSide(color: CouleursTaama.indigo),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onAnnuler,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Icon(Icons.cancel_outlined, size: 18),
                ),
              ],
            ),
          // Uniquement 'en_route' : avant acceptation, ni la navigation ni
          // le téléphone du client n'ont à être exposés au conducteur.
          if (demande['statut'] == 'en_route') ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) {
                    // depart_lat/depart_lng : vraie position de prise en
                    // charge du client, déjà dans la réponse API. Sans ça,
                    // EcranNavigation géocode le texte `destination` (où le
                    // client VEUT ALLER) et affiche ce point comme position
                    // du client — bug corrigé ici.
                    final departLat = (demande['depart_lat'] as num?)?.toDouble();
                    final departLng = (demande['depart_lng'] as num?)?.toDouble();
                    return EcranNavigation(
                      demandeId: demande['id'] is int
                          ? demande['id'] as int
                          : int.tryParse(demande['id'].toString()) ?? 0,
                      destination: demande['destination']?.toString() ?? '',
                      positionClient: (departLat != null && departLng != null)
                          ? LatLng(departLat, departLng)
                          : null,
                      telephoneClient: demande['client_telephone']?.toString(),
                    );
                  },
                ),
              ),
              icon: const Icon(Icons.navigation, size: 18),
              label: const Text('Naviguer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CouleursTaama.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Une carte de livraison Courier assignée au conducteur, en cours.
class _CarteLivraisonCourier extends StatelessWidget {
  final dynamic livraison;
  final VoidCallback onTap;

  const _CarteLivraisonCourier({required this.livraison, required this.onTap});

  static const _emojisCategorie = {
    'colis': '📦',
    'repas': '🍽️',
    'document': '📄',
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: const Border(left: BorderSide(color: Colors.orange, width: 4)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
        ),
        child: Row(
          children: [
            Text(
              _emojisCategorie[livraison['categorie']] ?? '📦',
              style: const TextStyle(fontSize: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    livraison['description_colis']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${livraison['adresse_collecte']} → ${livraison['adresse_livraison']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${livraison['prix'] ?? 0} FCFA',
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
