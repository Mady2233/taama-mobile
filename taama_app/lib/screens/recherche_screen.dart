// lib/screens/recherche_screen.dart
//
// Sélecteur de destination (v4). Le passager tape ou choisit une
// destination, renvoyée à l'écran appelant via Navigator.pop(context,
// DestinationChoisie) pour lancer une demande instantanée. Suggestions locales
// pendant la saisie (lib/services/recherche_lieux.dart), sans réseau : un lieu
// choisi part avec ses coordonnées.
//
// Style v4 (TaamaColors / TaamaText), cohérent avec l'accueil. Comportement
// et appels API identiques à la version précédente :
//  - favoris Domicile/Travail + libellés libres (ajout / suppression) ;
//  - destinations récentes dérivées de l'historique (max 5) ;
//  - destinations populaires de Bamako (liste fixe) ;
//  - saisie libre validée à la soumission.
//
// Corrigé vs v3 : contrôleur du dialogue d'ajout libéré, longueurs de saisie
// limitées, lecture défensive des favoris, logs en debug uniquement.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/recherche_lieux.dart';
import '../theme/taama_theme.dart';
import '../widgets/champ_adresse_lieu.dart';
import 'preciser_point_rue.dart';

const int _longueurMaxAdresse = 120;

void _journal(String message) {
  if (kDebugMode) debugPrint('[Recherche] $message');
}

/// Destination populaire : libellé, quartier et icône (plus d'emoji, pour
/// rester cohérent avec le reste de l'app v4).
class _LieuPopulaire {
  const _LieuPopulaire(this.nom, this.quartier, this.icone);
  final String nom;
  final String quartier;
  final IconData icone;
}

class EcranRecherche extends StatefulWidget {
  const EcranRecherche({super.key});

  @override
  State<EcranRecherche> createState() => _EcranRechercheState();
}

class _EcranRechercheState extends State<EcranRecherche> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<LieuTrouve> _suggestions = const [];

  static const List<_LieuPopulaire> _populaires = [
    _LieuPopulaire('Aéroport Modibo Keïta', 'Sénou', Icons.flight_rounded),
    _LieuPopulaire('Grand Marché', 'Centre-ville', Icons.storefront_rounded),
    _LieuPopulaire('ACI 2000', 'Hamdallaye', Icons.apartment_rounded),
    _LieuPopulaire('Hippodrome', 'Badalabougou', Icons.stadium_rounded),
    _LieuPopulaire('Kalaban Coro', 'Banlieue Sud', Icons.home_work_rounded),
    _LieuPopulaire('Magnambougou', 'Rive Droite', Icons.route_rounded),
    _LieuPopulaire('Sotuba', 'Zone Industrielle', Icons.factory_rounded),
    _LieuPopulaire('Commune VI', 'Yirimadjo', Icons.location_city_rounded),
  ];

  // Destinations récentes dérivées de l'historique (réutilise
  // mesDemandesClient() plutôt qu'un endpoint dédié), dédoublonnées, max 5.
  List<String> _recentes = const [];

  // Favoris (Domicile/Travail + libellés libres), chargés du backend.
  List<Map<String, dynamic>> _favoris = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _chargerDestinationsRecentes();
    _chargerFavoris();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ─── Données ───

  /// Échec silencieux volontaire : affichage de confort, pas critique.
  Future<void> _chargerFavoris() async {
    try {
      final favoris = await ApiService.mesAdressesFavorites();
      if (!mounted) return;
      setState(() => _favoris = favoris.whereType<Map<String, dynamic>>().toList());
    } catch (e) {
      _journal('Erreur chargement favoris : $e');
    }
  }

  Future<void> _chargerDestinationsRecentes() async {
    try {
      final demandes = await ApiService.mesDemandesClient();
      final vues = <String>{};
      final recentes = <String>[];
      for (final d in demandes) {
        if (d is! Map) continue;
        final destination = d['destination']?.toString();
        if (destination == null || destination.isEmpty) continue;
        if (vues.add(destination) && recentes.length < 5) {
          recentes.add(destination);
        }
      }
      if (mounted) setState(() => _recentes = recentes);
    } catch (e) {
      _journal('Erreur chargement destinations récentes : $e');
    }
  }

  Map<String, dynamic>? _favori(String libelle) {
    for (final f in _favoris) {
      if (f['libelle'] == libelle) return f;
    }
    return null;
  }

  // ─── Actions ───

  void _valider(String destination) {
    final d = destination.trim();
    if (d.isEmpty) return;
    final lieu = lieuExact(d);
    Navigator.pop(context, DestinationChoisie(d, lat: lieu?.lat, lng: lieu?.lng));
  }

  /// Une longue voie se précise d'abord sur la carte ; revenir sans confirmer
  /// laisse le client sur la recherche.
  Future<void> _choisirLieu(LieuTrouve lieu) async {
    final choisi = await preciserSiNecessaire(context, lieu);
    if (choisi == null || !mounted) return;
    Navigator.pop(context, DestinationChoisie(choisi.adresse, lat: choisi.lat, lng: choisi.lng));
  }

  /// Un favori enregistré depuis une suggestion garde ses coordonnées.
  void _validerFavori(Map<String, dynamic> favori) {
    final adresse = favori['adresse']?.toString() ?? '';
    final lat = (favori['latitude'] as num?)?.toDouble();
    final lng = (favori['longitude'] as num?)?.toDouble();
    if (adresse.isNotEmpty && lat != null && lng != null) {
      Navigator.pop(context, DestinationChoisie(adresse, lat: lat, lng: lng));
      return;
    }
    _valider(adresse);
  }

  Future<void> _onTapEmplacementFavori(String libelle) async {
    final favori = _favori(libelle);
    final adresse = favori?['adresse']?.toString();
    if (favori != null && adresse != null && adresse.isNotEmpty) {
      _validerFavori(favori);
      return;
    }
    await _ouvrirDialogueAjoutFavori(libelle);
  }

  Future<void> _ouvrirDialogueAjoutFavori(String libelle) async {
    final choix = await showDialog<DestinationChoisie>(
      context: context,
      builder: (_) => _DialogueAdresseFavori(libelle: libelle),
    );
    if (choix == null || !mounted) return;

    try {
      final enregistre = await ApiService.enregistrerAdresseFavorite(
        libelle: libelle,
        adresse: choix.nom,
        latitude: choix.lat,
        longitude: choix.lng,
      );
      if (!mounted) return;
      // enregistrerAdresseFavorite renvoie toujours un Map<String, dynamic>.
      setState(() {
        _favoris = [
          ..._favoris.where((f) => f['libelle'] != libelle),
          enregistre,
        ];
      });
      Navigator.pop(context, choix);
    } catch (e) {
      _journal('Erreur enregistrement favori : $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'enregistrer l'adresse. Réessayez.")),
      );
    }
  }

  Future<void> _confirmerSuppressionFavori(Map<String, dynamic> favori) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer « ${favori['libelle']} » ?'),
        content: Text(favori['adresse']?.toString() ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: TaamaColors.danger),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    final id = favori['id'];
    if (id is! int) return;
    try {
      await ApiService.supprimerAdresseFavorite(id);
      if (mounted) setState(() => _favoris = _favoris.where((f) => f['id'] != id).toList());
    } catch (e) {
      _journal('Erreur suppression favori : $e');
    }
  }

  // ─── Construction ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TaamaColors.background,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  _BoutonRetour(onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 12),
                  Expanded(child: _champRecherche()),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              // Le clavier reste ouvert : la liste doit pouvoir défiler dessous.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: _ctrl.text.trim().isNotEmpty
                  ? _contenuSuggestions(_ctrl.text.trim())
                  : [
                _sectionFavoris(),
                if (_recentes.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const _TitreSection(icone: Icons.schedule_rounded, texte: 'Récents'),
                  const SizedBox(height: 10),
                  for (final destination in _recentes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LigneLieu(
                        icone: Icons.schedule_rounded,
                        titre: destination,
                        onTap: () => _valider(destination),
                      ),
                    ),
                ],
                const SizedBox(height: 22),
                const _TitreSection(
                  icone: Icons.place_rounded,
                  texte: 'Destinations populaires',
                ),
                const SizedBox(height: 10),
                _grillePopulaires(),
                const SizedBox(height: 22),
                _carteSaisieLibre(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _contenuSuggestions(String saisie) {
    return [
      if (_suggestions.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Aucun lieu connu pour « $saisie ». Vous pouvez quand même l’utiliser.',
            style: TaamaText.body.copyWith(fontSize: 13, color: TaamaColors.textSecondary),
          ),
        ),
      for (final lieu in _suggestions)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _LigneLieu(
            icone: Icons.place_rounded,
            titre: lieu.nom,
            sousTitre: lieu.detail,
            onTap: () => _choisirLieu(lieu),
          ),
        ),
      _LigneLieu(
        icone: Icons.edit_location_alt_rounded,
        titre: 'Utiliser « $saisie »',
        couleurIcone: TaamaColors.textSecondary,
        onTap: () => _valider(saisie),
      ),
    ];
  }

  Widget _champRecherche() {
    return Material(
      color: TaamaColors.surface,
      borderRadius: BorderRadius.circular(TaamaRadius.lg),
      elevation: 3,
      shadowColor: TaamaColors.textPrimary.withValues(alpha: 0.12),
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: [LengthLimitingTextInputFormatter(_longueurMaxAdresse)],
        onChanged: (texte) => setState(() => _suggestions = rechercherLieux(texte)),
        onSubmitted: _valider,
        style: TaamaText.body.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        cursorColor: TaamaColors.primary,
        decoration: InputDecoration(
          hintText: 'Où allez-vous ?',
          hintStyle: TaamaText.body.copyWith(
            color: TaamaColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(Icons.search_rounded, color: TaamaColors.primary),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: TaamaColors.textSecondary,
                  onPressed: () {
                    _ctrl.clear();
                    setState(() => _suggestions = const []);
                  },
                ),
          filled: true,
          fillColor: TaamaColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(TaamaRadius.lg),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _sectionFavoris() {
    final domicile = _favori('Domicile');
    final travail = _favori('Travail');
    final autres = _favoris
        .where((f) => f['libelle'] != 'Domicile' && f['libelle'] != 'Travail')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TitreSection(icone: Icons.star_rounded, texte: 'Favoris'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ChipFavori(
                icone: Icons.home_rounded,
                libelle: 'Domicile',
                adresse: domicile?['adresse']?.toString(),
                onTap: () => _onTapEmplacementFavori('Domicile'),
                onLongPress: domicile == null ? null : () => _confirmerSuppressionFavori(domicile),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ChipFavori(
                icone: Icons.work_rounded,
                libelle: 'Travail',
                adresse: travail?['adresse']?.toString(),
                onTap: () => _onTapEmplacementFavori('Travail'),
                onLongPress: travail == null ? null : () => _confirmerSuppressionFavori(travail),
              ),
            ),
          ],
        ),
        for (final f in autres)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _LigneLieu(
              icone: Icons.star_rounded,
              couleurIcone: TaamaColors.star,
              titre: f['libelle']?.toString() ?? '',
              sousTitre: f['adresse']?.toString(),
              onTap: () => _validerFavori(f),
              onLongPress: () => _confirmerSuppressionFavori(f),
            ),
          ),
      ],
    );
  }

  Widget _grillePopulaires() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: [
        for (final lieu in _populaires)
          _TuilePopulaire(lieu: lieu, onTap: () => _valider(lieu.nom)),
      ],
    );
  }

  Widget _carteSaisieLibre() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TaamaColors.primarySoft,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: TaamaColors.primary,
              borderRadius: BorderRadius.circular(TaamaRadius.md),
            ),
            child: const Icon(Icons.edit_location_alt_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Autre destination ?',
                    style: TaamaText.body.copyWith(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  'Tapez le nom du lieu ou du quartier dans la barre en haut.',
                  style: TaamaText.body.copyWith(
                    color: TaamaColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.keyboard_arrow_up_rounded, color: TaamaColors.primary),
        ],
      ),
    );
  }
}

// ─── Widgets privés ───

class _BoutonRetour extends StatelessWidget {
  const _BoutonRetour({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.surfaceMuted,
      borderRadius: BorderRadius.circular(TaamaRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(TaamaRadius.md),
        onTap: onTap,
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.arrow_back_rounded, color: TaamaColors.textPrimary, size: 22),
        ),
      ),
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection({required this.icone, required this.texte});
  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 18, color: TaamaColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texte,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TaamaText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// Ligne de lieu (récent, favori libre) : icône ronde + titre (+ sous-titre).
class _LigneLieu extends StatelessWidget {
  const _LigneLieu({
    required this.icone,
    required this.titre,
    required this.onTap,
    this.sousTitre,
    this.onLongPress,
    this.couleurIcone = TaamaColors.primary,
  });

  final IconData icone;
  final String titre;
  final String? sousTitre;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color couleurIcone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.surface,
      borderRadius: BorderRadius.circular(TaamaRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(TaamaRadius.md),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TaamaRadius.md),
            border: Border.all(color: TaamaColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: couleurIcone.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icone, color: couleurIcone, size: 16),
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
                      style: TaamaText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    if (sousTitre != null && sousTitre!.isNotEmpty)
                      Text(
                        sousTitre!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TaamaText.body.copyWith(
                          fontSize: 11,
                          color: TaamaColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.north_west_rounded, color: TaamaColors.textSecondary, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _TuilePopulaire extends StatelessWidget {
  const _TuilePopulaire({required this.lieu, required this.onTap});
  final _LieuPopulaire lieu;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.surface,
      borderRadius: BorderRadius.circular(TaamaRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(TaamaRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TaamaRadius.md),
            border: Border.all(color: TaamaColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: TaamaColors.primarySoft,
                  borderRadius: BorderRadius.circular(TaamaRadius.sm),
                ),
                child: Icon(lieu.icone, color: TaamaColors.primary, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      lieu.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TaamaText.body.copyWith(fontSize: 11.5, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      lieu.quartier,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TaamaText.body.copyWith(
                        fontSize: 9.5,
                        color: TaamaColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Emplacement fixe Domicile/Travail. Affiche l'adresse si définie, sinon
/// « Ajouter ». Appui long : supprimer (désactivé si rien à supprimer).
class _ChipFavori extends StatelessWidget {
  const _ChipFavori({
    required this.icone,
    required this.libelle,
    required this.adresse,
    required this.onTap,
    required this.onLongPress,
  });

  final IconData icone;
  final String libelle;
  final String? adresse;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final defini = adresse != null && adresse!.isNotEmpty;
    return Material(
      color: defini ? TaamaColors.primarySoft : TaamaColors.surfaceMuted,
      borderRadius: BorderRadius.circular(TaamaRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(TaamaRadius.md),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TaamaRadius.md),
            border: Border.all(
              color: defini ? TaamaColors.primary.withValues(alpha: 0.25) : TaamaColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icone, size: 16, color: defini ? TaamaColors.primary : TaamaColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    libelle,
                    style: TaamaText.body.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: defini ? TaamaColors.primary : TaamaColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                defini ? adresse! : 'Ajouter',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TaamaText.body.copyWith(
                  fontSize: 11,
                  color: defini ? TaamaColors.textSecondary : TaamaColors.primary,
                  fontWeight: defini ? FontWeight.w500 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialogue d'ajout d'adresse favorite : possède son contrôleur (libéré avec
/// le dialogue), longueur limitée, validation du champ vide. Renvoie l'adresse
/// et, si elle vient d'une suggestion ou d'un nom connu, ses coordonnées.
class _DialogueAdresseFavori extends StatefulWidget {
  const _DialogueAdresseFavori({required this.libelle});
  final String libelle;

  @override
  State<_DialogueAdresseFavori> createState() => _DialogueAdresseFavoriState();
}

class _DialogueAdresseFavoriState extends State<_DialogueAdresseFavori> {
  final _ctrl = TextEditingController();
  LieuTrouve? _lieu;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _valider() {
    final adresse = _ctrl.text.trim();
    if (adresse.isEmpty) return;
    final lieu = _lieu ?? lieuExact(adresse);
    Navigator.pop(context, DestinationChoisie(adresse, lat: lieu?.lat, lng: lieu?.lng));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text('Adresse « ${widget.libelle} »'),
      content: ChampAdresseLieu(
        controleur: _ctrl,
        autofocus: true,
        longueurMax: _longueurMaxAdresse,
        onLieu: (lieu) => _lieu = lieu,
        onValider: _valider,
        decoration: const InputDecoration(hintText: 'Ex : Hippodrome, Bamako'),
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