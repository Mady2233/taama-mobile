import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    // Auto-focus au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
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
}
