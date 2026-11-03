import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../theme/taama_theme.dart';
import '../utils/format.dart';
import '../widgets/photo_avatar.dart';

/// Écran de profil (v4) : téléphone en lecture seule, modification du nom, et
/// historique combiné réservations + demandes instantanées, du plus récent au
/// plus ancien. Logique inchangée ; habillage TaamaColors/TaamaText, lecture
/// défensive de l'historique, longueurs de saisie limitées, logs en debug.
class EcranProfil extends StatefulWidget {
  const EcranProfil({super.key});

  @override
  State<EcranProfil> createState() => _EcranProfilState();
}

class _EcranProfilState extends State<EcranProfil> {
  static const int _longueurMaxNom = 50;

  bool _chargement = true;
  Map<String, dynamic>? _profil;
  List<Map<String, dynamic>> _historique = const [];

  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _nomController = TextEditingController();
  bool _modeEdition = false;
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _prenomController.dispose();
    _nomController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final profil = await ApiService.monProfil();
      final reservations = await ApiService.mesReservations();
      final demandes = await ApiService.mesDemandesClient();

      // Fusion défensive des deux historiques, avec un champ "_type" pour
      // savoir comment afficher chaque entrée. Une entrée mal formée est
      // ignorée plutôt que de faire planter l'écran.
      final combine = <Map<String, dynamic>>[
        for (final r in reservations)
          if (r is Map<String, dynamic>) {...r, '_type': 'reservation'},
        for (final d in demandes)
          if (d is Map<String, dynamic>) {...d, '_type': 'demande'},
      ];
      combine.sort((a, b) {
        final dateA = DateTime.tryParse(a['cree_le']?.toString() ?? '') ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['cree_le']?.toString() ?? '') ?? DateTime(2000);
        return dateB.compareTo(dateA);
      });

      if (!mounted) return;
      setState(() {
        _profil = profil;
        _historique = combine;
        _prenomController.text = profil['first_name']?.toString() ?? '';
        _nomController.text = profil['last_name']?.toString() ?? '';
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Profil] Erreur chargement : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _enregistrerProfil() async {
    setState(() => _enregistrement = true);
    try {
      final profil = await ApiService.modifierProfil(
        prenom: _prenomController.text.trim(),
        nom: _nomController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _profil = profil;
        _modeEdition = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la mise à jour')),
      );
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  String get _nomComplet {
    final prenom = _profil?['first_name']?.toString() ?? '';
    final nom = _profil?['last_name']?.toString() ?? '';
    return '$prenom $nom'.trim();
  }

  /// Icône, titre, sous-titre et couleur d'une entrée d'historique.
  (IconData, String, String, Color) _infosEntree(Map<String, dynamic> entree) {
    if (entree['_type'] == 'reservation') {
      final trajet = entree['trajet_propose'];
      final statut = entree['statut']?.toString() ?? '';
      final couleur = switch (statut) {
        'confirmee' => TaamaColors.success,
        'refusee' => TaamaColors.danger,
        'annulee' => TaamaColors.textSecondary,
        _ => TaamaColors.star,
      };
      if (trajet is Map) {
        final prix = formaterFcfaApi(trajet['prix_par_place']);
        return (
          Icons.event_seat_rounded,
          '${trajet['depart'] ?? '?'} → ${trajet['arrivee'] ?? '?'}',
          prix == null ? 'Réservation' : 'Réservation • $prix',
          couleur,
        );
      }
      return (Icons.event_seat_rounded, 'Réservation', 'Réservation', couleur);
    } else {
      final statut = entree['statut']?.toString() ?? '';
      final couleur = switch (statut) {
        'termine' => TaamaColors.success,
        'annule' => TaamaColors.textSecondary,
        'en_route' => TaamaColors.primary,
        _ => TaamaColors.star,
      };
      final prix = formaterFcfaApi(entree['prix_estime']);
      return (
        Icons.local_taxi_rounded,
        entree['destination']?.toString() ?? 'Destination inconnue',
        prix == null ? 'Course' : 'Course • $prix',
        couleur,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TaamaColors.background,
      appBar: AppBar(
        title: const Text('Mon profil'),
        backgroundColor: TaamaColors.background,
        foregroundColor: TaamaColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: TaamaColors.primary))
          : RefreshIndicator(
              color: TaamaColors.primary,
              onRefresh: _charger,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _carteIdentite(),
                  const SizedBox(height: 24),
                  Text('Historique', style: TaamaText.title.copyWith(fontSize: 17)),
                  const SizedBox(height: 12),
                  if (_historique.isEmpty)
                    _etatVide()
                  else
                    for (final entree in _historique) _ligneHistorique(entree),
                ],
              ),
            ),
    );
  }

  Widget _carteIdentite() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        boxShadow: TaamaShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoAvatar(nom: _nomComplet, diametre: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profil?['telephone']?.toString() ?? '',
                      style: TaamaText.muted.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _nomComplet.isEmpty ? 'Nom non renseigné' : _nomComplet,
                      style: TaamaText.title.copyWith(fontSize: 18),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _modeEdition ? 'Fermer' : 'Modifier',
                icon: Icon(
                  _modeEdition ? Icons.close_rounded : Icons.edit_rounded,
                  color: TaamaColors.textSecondary,
                ),
                onPressed: () => setState(() => _modeEdition = !_modeEdition),
              ),
            ],
          ),
          if (_modeEdition) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _prenomController,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(_longueurMaxNom)],
              decoration: const InputDecoration(labelText: 'Prénom'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nomController,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(_longueurMaxNom)],
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _enregistrement ? null : _enregistrerProfil,
                child: _enregistrement
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enregistrer'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _etatVide() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        border: Border.all(color: TaamaColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.history_rounded, size: 32, color: TaamaColors.textSecondary),
          const SizedBox(height: 10),
          Text(
            'Aucun trajet pour l’instant',
            style: TaamaText.body.copyWith(color: TaamaColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _ligneHistorique(Map<String, dynamic> entree) {
    final (icone, titre, sousTitre, couleur) = _infosEntree(entree);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.md),
        border: Border.all(color: TaamaColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: couleur.withValues(alpha: 0.15),
            child: Icon(icone, color: couleur, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TaamaText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  sousTitre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TaamaText.body.copyWith(
                    fontSize: 12,
                    color: TaamaColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}