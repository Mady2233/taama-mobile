import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';

/// Sélecteur de destination texte : le passager tape ou choisit une
/// destination populaire, qui est renvoyée (Navigator.pop) à l'écran
/// appelant pour lancer une demande instantanée. Ne recherche plus d'offres
/// publiées (dispatch pur) — c'est un simple sélecteur de destination.
class EcranRecherche extends StatefulWidget {
  const EcranRecherche({super.key});

  @override
  State<EcranRecherche> createState() => _EcranRechercheState();
}

class _EcranRechercheState extends State<EcranRecherche> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  // Destinations populaires à Bamako
  final List<Map<String, String>> _populaires = [
    {'nom': 'Aéroport Modibo Keïta', 'quartier': 'Sénou', 'emoji': '✈️'},
    {'nom': 'Grand Marché', 'quartier': 'Centre-ville', 'emoji': '🛒'},
    {'nom': 'ACI 2000', 'quartier': 'Hamdallaye', 'emoji': '🏢'},
    {'nom': 'Hippodrome', 'quartier': 'Badalabougou', 'emoji': '🏟️'},
    {'nom': 'Kalaban Coro', 'quartier': 'Banlieue Sud', 'emoji': '🏘️'},
    {'nom': 'Magnambougou', 'quartier': 'Rive Droite', 'emoji': '🌉'},
    {'nom': 'Sotuba', 'quartier': 'Zone Industrielle', 'emoji': '🏭'},
    {'nom': 'Commune VI', 'quartier': 'Yirimadjo', 'emoji': '🏙️'},
  ];

  // Destinations récentes du passager, dérivées de son historique de
  // demandes (aucun modèle backend dédié — on réutilise mesDemandesClient()
  // plutôt que d'ajouter un nouvel endpoint pour une simple liste d'affichage).
  List<String> _recentes = [];

  // Adresses favorites du passager (Domicile/Travail + éventuels libellés
  // personnalisés) — chargées depuis le backend, gérées entièrement sur cet
  // écran (ajout via les deux emplacements fixes, suppression par appui long).
  List<Map<String, dynamic>> _favoris = [];

  @override
  void initState() {
    super.initState();
    // Auto-focus au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
    _chargerDestinationsRecentes();
    _chargerFavoris();
  }

  /// Même échec silencieux volontaire que _chargerDestinationsRecentes.
  Future<void> _chargerFavoris() async {
    try {
      final favoris = await ApiService.mesAdressesFavorites();
      if (mounted) {
        setState(() => _favoris = favoris.cast<Map<String, dynamic>>());
      }
    } catch (e) {
      debugPrint('Erreur chargement favoris : $e');
    }
  }

  Map<String, dynamic>? _favori(String libelle) {
    for (final f in _favoris) {
      if (f['libelle'] == libelle) return f;
    }
    return null;
  }

  /// Emplacement fixe (Domicile/Travail) : sélectionne l'adresse déjà
  /// enregistrée, ou propose de la définir si ce n'est pas encore fait.
  Future<void> _onTapEmplacementFavori(String libelle) async {
    final favori = _favori(libelle);
    if (favori != null) {
      _valider(favori['adresse'] as String);
      return;
    }
    await _ouvrirDialogueAjoutFavori(libelle);
  }

  Future<void> _ouvrirDialogueAjoutFavori(String libelle) async {
    final ctrl = TextEditingController();
    final adresse = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Adresse "$libelle"'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex : Hippodrome, Bamako'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: CouleursTaama.terreCuite,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (adresse == null || adresse.isEmpty || !mounted) return;

    try {
      final enregistre = await ApiService.enregistrerAdresseFavorite(
        libelle: libelle,
        adresse: adresse,
      );
      if (!mounted) return;
      setState(() {
        _favoris = [
          ..._favoris.where((f) => f['libelle'] != libelle),
          enregistre,
        ];
      });
      _valider(adresse);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Erreur : ${e.toString().replaceAll('Exception: ', '')}')));
    }
  }

  Future<void> _confirmerSuppressionFavori(Map<String, dynamic> favori) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer "${favori['libelle']}" ?'),
        content: Text(favori['adresse']?.toString() ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    try {
      await ApiService.supprimerAdresseFavorite(favori['id'] as int);
      if (mounted) {
        setState(() => _favoris.removeWhere((f) => f['id'] == favori['id']));
      }
    } catch (e) {
      debugPrint('Erreur suppression favori : $e');
    }
  }

  /// Échec silencieux volontaire : les destinations récentes sont un
  /// confort d'affichage, pas une donnée critique — un historique vide en
  /// cas d'erreur réseau laisse simplement la section masquée.
  Future<void> _chargerDestinationsRecentes() async {
    try {
      final demandes = await ApiService.mesDemandesClient();
      // Plus récent d'abord (l'API renvoie déjà les demandes triées par
      // date de création décroissante), dédoublonné, limité à 5 pour ne
      // pas repousser les destinations populaires hors écran.
      final vues = <String>{};
      final recentes = <String>[];
      for (final d in demandes) {
        final destination = (d as Map<String, dynamic>)['destination']?.toString();
        if (destination == null || destination.isEmpty) continue;
        if (vues.add(destination) && recentes.length < 5) {
          recentes.add(destination);
        }
      }
      if (mounted) setState(() => _recentes = recentes);
    } catch (e) {
      debugPrint('Erreur chargement destinations récentes : $e');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _valider(String destination) {
    Navigator.pop(context, destination);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ─── Header gradient ───
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1C2B4A), Color(0xFF3D2B6B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barre retour + champ recherche
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.arrow_back,
                                color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: _ctrl,
                              focusNode: _focus,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (v) {
                                if (v.trim().isNotEmpty) _valider(v.trim());
                              },
                              style: const TextStyle(
                                fontSize: 15,
                                color: CouleursTaama.indigo,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Où allez-vous ?',
                                hintStyle: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontWeight: FontWeight.normal),
                                prefixIcon: const Icon(Icons.search,
                                    color: CouleursTaama.indigo, size: 20),
                                suffixIcon: _ctrl.text.isNotEmpty
                                    ? GestureDetector(
                                        onTap: () {
                                          _ctrl.clear();
                                          setState(() {});
                                        },
                                        child: const Icon(Icons.close,
                                            color: Colors.grey, size: 18),
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ─── Contenu ───
          Expanded(
            child: _buildSuggestionsEtPopulaires(),
          ),
        ],
      ),
    );
  }

  // ─── Suggestions populaires ───
  Widget _buildSuggestionsEtPopulaires() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section "Favoris" — toujours visible (contrairement aux
          // récentes/populaires) : les deux emplacements Domicile/Travail
          // servent aussi de point d'entrée pour les enregistrer.
          _buildSectionFavoris(),
          const SizedBox(height: 20),

          // Section "Destinations récentes" — masquée tant qu'aucun
          // historique n'est chargé (premier trajet, ou erreur réseau
          // silencieuse, voir _chargerDestinationsRecentes).
          if (_recentes.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.history,
                    color: CouleursTaama.indigo, size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Destinations récentes',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: CouleursTaama.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final destination in _recentes) ...[
              GestureDetector(
                onTap: () => _valider(destination),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: CouleursTaama.indigo.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.history,
                            color: CouleursTaama.indigo, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          destination,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: CouleursTaama.indigo,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.north_west,
                          color: Colors.grey.shade400, size: 16),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],

          // Section "Destinations populaires"
          Row(
            children: [
              const Icon(Icons.local_fire_department,
                  color: CouleursTaama.terreCuite, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Destinations populaires à Bamako',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: CouleursTaama.indigo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Grille de destinations
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.8,
            children: _populaires.map((lieu) {
              return GestureDetector(
                onTap: () => _valider(lieu['nom']!),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: CouleursTaama.sable,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Text(lieu['emoji']!,
                          style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Text(
                              lieu['nom']!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                                color: CouleursTaama.indigo,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              lieu['quartier']!,
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Section "Saisie libre"
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  CouleursTaama.indigo.withValues(alpha: 0.05),
                  CouleursTaama.terreCuite.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: CouleursTaama.indigo.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: CouleursTaama.indigo,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_location_alt,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Autre destination ?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: CouleursTaama.indigo,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Tape le nom du quartier dans la barre ci-dessus',
                        style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.keyboard_arrow_up,
                    color: CouleursTaama.terreCuite),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Tip demande instantanée
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CouleursTaama.terreCuite.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: CouleursTaama.terreCuite.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                const Text('⚡', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pas de trajet disponible ?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: CouleursTaama.terreCuite,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'Fais une demande instantanée — un conducteur'
                        ' viendra te chercher.',
                        style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Section Favoris ───
  Widget _buildSectionFavoris() {
    final domicile = _favori('Domicile');
    final travail = _favori('Travail');
    final autres = _favoris
        .where((f) => f['libelle'] != 'Domicile' && f['libelle'] != 'Travail')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.star_rounded, color: CouleursTaama.or, size: 18),
            const SizedBox(width: 6),
            const Text(
              'Favoris',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: CouleursTaama.indigo,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ChipFavori(
                icone: Icons.home_rounded,
                libelle: 'Domicile',
                adresse: domicile?['adresse']?.toString(),
                onTap: () => _onTapEmplacementFavori('Domicile'),
                onLongPress: domicile != null
                    ? () => _confirmerSuppressionFavori(domicile)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ChipFavori(
                icone: Icons.work_rounded,
                libelle: 'Travail',
                adresse: travail?['adresse']?.toString(),
                onTap: () => _onTapEmplacementFavori('Travail'),
                onLongPress: travail != null
                    ? () => _confirmerSuppressionFavori(travail)
                    : null,
              ),
            ),
          ],
        ),
        for (final f in autres) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _valider(f['adresse'] as String),
            onLongPress: () => _confirmerSuppressionFavori(f),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: CouleursTaama.or.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.star_rounded,
                        color: CouleursTaama.or, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f['libelle']?.toString() ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: CouleursTaama.indigo)),
                        Text(
                          f['adresse']?.toString() ?? '',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Emplacement fixe de favori (Domicile/Travail) : affiche l'adresse
/// enregistrée si elle existe, sinon une invitation à l'ajouter. L'appui
/// long ne fait rien tant qu'aucune adresse n'est enregistrée (onLongPress
/// null) — rien à supprimer dans ce cas.
class _ChipFavori extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final String? adresse;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ChipFavori({
    required this.icone,
    required this.libelle,
    required this.adresse,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final estDefini = adresse != null && adresse!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: estDefini
              ? CouleursTaama.indigo.withValues(alpha: 0.05)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: estDefini
                ? CouleursTaama.indigo.withValues(alpha: 0.2)
                : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icone,
                    size: 16,
                    color: estDefini
                        ? CouleursTaama.indigo
                        : Colors.grey.shade400),
                const SizedBox(width: 6),
                Text(libelle,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: estDefini
                            ? CouleursTaama.indigo
                            : Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              estDefini ? adresse! : 'Ajouter',
              style: TextStyle(
                fontSize: 11,
                color: estDefini ? Colors.grey.shade600 : CouleursTaama.terreCuite,
                fontWeight: estDefini ? FontWeight.normal : FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
