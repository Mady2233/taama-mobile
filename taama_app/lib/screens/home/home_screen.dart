// lib/screens/home/home_screen.dart
//
// Accueil client Taama — v3 (maquette validée).
//
// Widget purement présentationnel : aucune logique réseau, aucun état global,
// aucune valeur en dur. Tout arrive par les paramètres, toute action remonte
// par un callback. La logique (appels API, cache, permissions) vit dans
// home_page.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/taama_theme.dart';
import '../../utils/format.dart';
import '../../widgets/photo_avatar.dart';
import '../../widgets/taama_map.dart' show TaamaMapTiles, attributionCarteTaama;

// ---------------------------------------------------------------------------
// Modèles d'affichage
// ---------------------------------------------------------------------------

enum TypeAdresse { domicile, travail, autre }

/// Raccourci proposé sous le champ de recherche.
/// [dureeMinutes] vient du serveur (OSRM) ; null → aucune durée affichée.
class SuggestionDestination {
  const SuggestionDestination({
    required this.id,
    required this.libelle,
    this.dureeMinutes,
    this.type = TypeAdresse.autre,
    this.miseEnAvant = false,
  });

  final String id;
  final String libelle;
  final int? dureeMinutes;
  final TypeAdresse type;

  /// Suggestion la plus probable à cette heure. Une seule à la fois.
  final bool miseEnAvant;
}

/// Chauffeur affiché sur la bande carte.
/// Le backend ne renvoie que prénom + initiale : jamais le nom complet
/// ni le téléphone tant que la course n'est pas acceptée.
class ConducteurProche {
  const ConducteurProche({
    required this.id,
    required this.nomCourt,
    required this.position,
    this.urlPhoto,
    this.note,
    this.modeleVehicule,
    this.minutesAvant,
    this.estMoto = false,
  });

  final String id;
  final String nomCourt;
  final LatLng position;
  final String? urlPhoto;
  final double? note;
  final String? modeleVehicule;
  final int? minutesAvant;
  final bool estMoto;
}

/// Service commandable, avec son prix plancher calculé côté serveur.
class ServiceCourse {
  const ServiceCourse({
    required this.code,
    required this.nom,
    required this.argument,
    required this.prixMinFcfa,
    this.climatise = false,
    this.disponible = true,
    this.miseEnAvant = false,
  });

  final String code;
  final String nom;
  final String argument;
  final int prixMinFcfa;
  final bool climatise;
  final bool disponible;
  final bool miseEnAvant;
}

/// Dernière course terminée, pour la recommander en un tap.
class DerniereCourse {
  const DerniereCourse({
    required this.id,
    required this.depart,
    required this.arrivee,
    required this.prixFcfa,
  });

  final String id;
  final String depart;
  final String arrivee;
  final int prixFcfa;
}

// ---------------------------------------------------------------------------
// Écran
// ---------------------------------------------------------------------------

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.prenom,
    required this.quartier,
    required this.soldeFcfa,
    required this.services,
    required this.suggestions,
    required this.conducteursProches,
    required this.onChercherDestination,
    required this.onSuggestion,
    required this.onAjouterAdresse,
    required this.onService,
    required this.onReserver,
    required this.onColis,
    required this.onPortefeuille,
    required this.onProfil,
    required this.onRecentrerCarte,
    required this.onActualiser,
    this.positionClient,
    this.urlPhotoProfil,
    this.derniereCourse,
    this.onRefaireCourse,
    this.onDicterDestination,
    this.chargementConducteurs = false,
  });

  /// Prénom seul. Vide ou null → salutation neutre (jamais le numéro).
  final String? prenom;

  /// Quartier détecté. Null → on n'affiche pas la ligne.
  final String? quartier;
  final String? urlPhotoProfil;
  final int soldeFcfa;

  final List<ServiceCourse> services;
  final List<SuggestionDestination> suggestions;
  final List<ConducteurProche> conducteursProches;
  final LatLng? positionClient;
  final bool chargementConducteurs;
  final DerniereCourse? derniereCourse;

  final VoidCallback onChercherDestination;
  final ValueChanged<SuggestionDestination> onSuggestion;
  final VoidCallback onAjouterAdresse;
  final ValueChanged<ServiceCourse> onService;
  final VoidCallback onReserver;
  final VoidCallback onColis;
  final VoidCallback onPortefeuille;
  final VoidCallback onProfil;
  final VoidCallback onRecentrerCarte;
  final VoidCallback? onRefaireCourse;
  final VoidCallback? onDicterDestination;
  final Future<void> Function() onActualiser;

  ConducteurProche? get _plusProche {
    if (conducteursProches.isEmpty) return null;
    final tries = [...conducteursProches]..sort((a, b) {
        final ma = a.minutesAvant ?? 9999;
        final mb = b.minutesAvant ?? 9999;
        return ma.compareTo(mb);
      });
    return tries.first;
  }

  @override
  Widget build(BuildContext context) {
    // Barre de statut en icônes claires : l'en-tête (_EnTete) est en
    // TaamaColors.navy, un fond sombre où des icônes de statut foncées
    // (style par défaut) seraient illisibles.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      backgroundColor: TaamaColors.background,
      body: RefreshIndicator(
        color: TaamaColors.primary,
        edgeOffset: 200,
        onRefresh: onActualiser,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _EnTete(
              prenom: prenom,
              quartier: quartier,
              urlPhotoProfil: urlPhotoProfil,
              soldeFcfa: soldeFcfa,
              suggestions: suggestions,
              onProfil: onProfil,
              onPortefeuille: onPortefeuille,
              onChercherDestination: onChercherDestination,
              onSuggestion: onSuggestion,
              onAjouterAdresse: onAjouterAdresse,
              onDicterDestination: onDicterDestination,
            ),
            const _BandeConfiance(),
            _BandeCarte(
              positionClient: positionClient,
              conducteurs: conducteursProches,
              plusProche: _plusProche,
              chargement: chargementConducteurs,
              onRecentrer: onRecentrerCarte,
            ),
            Padding(
              padding: const EdgeInsets.all(TaamaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (services.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Expanded(
                          child: Text(
                            'Choisir un service',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: TaamaColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          'Prix annoncé avant le départ',
                          style: const TextStyle(
                            fontSize: 12,
                            color: TaamaColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TaamaSpacing.md),
                    for (final s in services) ...[
                      _LigneService(service: s, onTap: () => onService(s)),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: TaamaSpacing.xs),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _ActionSecondaire(
                          icone: Icons.event_available_rounded,
                          couleur: TaamaColors.success,
                          libelle: 'Réserver',
                          onTap: onReserver,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionSecondaire(
                          icone: Icons.inventory_2_rounded,
                          couleur: TaamaColors.warning,
                          libelle: 'Colis',
                          onTap: onColis,
                        ),
                      ),
                    ],
                  ),
                  if (derniereCourse != null) ...[
                    const SizedBox(height: TaamaSpacing.lg),
                    _CarteDerniereCourse(
                      course: derniereCourse!,
                      onTap: onRefaireCourse,
                    ),
                  ],
                  if (soldeFcfa <= 0) ...[
                    const SizedBox(height: TaamaSpacing.lg),
                    _BandeauPortefeuille(onRecharger: onPortefeuille),
                  ],
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

// ---------------------------------------------------------------------------
// En-tête bleu nuit
// ---------------------------------------------------------------------------

class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.prenom,
    required this.quartier,
    required this.urlPhotoProfil,
    required this.soldeFcfa,
    required this.suggestions,
    required this.onProfil,
    required this.onPortefeuille,
    required this.onChercherDestination,
    required this.onSuggestion,
    required this.onAjouterAdresse,
    required this.onDicterDestination,
  });

  final String? prenom;
  final String? quartier;
  final String? urlPhotoProfil;
  final int soldeFcfa;
  final List<SuggestionDestination> suggestions;
  final VoidCallback onProfil;
  final VoidCallback onPortefeuille;
  final VoidCallback onChercherDestination;
  final ValueChanged<SuggestionDestination> onSuggestion;
  final VoidCallback onAjouterAdresse;
  final VoidCallback? onDicterDestination;

  String _titre() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Où allez-vous\nce matin ?';
    if (h < 18) return 'Où allez-vous ?';
    return 'Où allez-vous\nce soir ?';
  }

  @override
  Widget build(BuildContext context) {
    final nom = (prenom ?? '').trim();
    final haut = MediaQuery.paddingOf(context).top;

    return Container(
      width: double.infinity,
      color: TaamaColors.navy,
      padding: EdgeInsets.fromLTRB(
        TaamaSpacing.lg,
        haut + TaamaSpacing.md,
        TaamaSpacing.lg,
        TaamaSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Mon compte',
                child: InkWell(
                  onTap: onProfil,
                  borderRadius: BorderRadius.circular(TaamaRadius.md),
                  child: PhotoAvatar(
                    nom: nom,
                    urlPhoto: urlPhotoProfil,
                    diametre: 42,
                    forme: BoxShape.rectangle,
                    couleurFond: TaamaColors.primary,
                    couleurTexte: TaamaColors.textOnDark,
                  ),
                ),
              ),
              const SizedBox(width: TaamaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nom.isEmpty ? 'Bonjour' : 'Bonjour, $nom',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TaamaColors.textOnDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (quartier != null && quartier!.isNotEmpty)
                      Text(
                        quartier!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TaamaColors.onNavyMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              _PuceSolde(soldeFcfa: soldeFcfa, onTap: onPortefeuille),
            ],
          ),
          const SizedBox(height: TaamaSpacing.xl),
          Text(
            _titre(),
            style: const TextStyle(
              color: TaamaColors.textOnDark,
              fontSize: 27,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: TaamaSpacing.md),
          _ChampDestination(
            onTap: onChercherDestination,
            onDicter: onDicterDestination,
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final s in suggestions) ...[
                    _PuceSuggestion(
                      suggestion: s,
                      onTap: () => onSuggestion(s),
                    ),
                    const SizedBox(width: TaamaSpacing.sm),
                  ],
                  _PuceAjout(onTap: onAjouterAdresse),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PuceSolde extends StatelessWidget {
  const _PuceSolde({required this.soldeFcfa, required this.onTap});

  final int soldeFcfa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Portefeuille, ${formaterFcfa(soldeFcfa)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TaamaRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: TaamaColors.primary,
            borderRadius: BorderRadius.circular(TaamaRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  size: 15, color: TaamaColors.textOnDark),
              const SizedBox(width: 6),
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: soldeFcfa),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, valeur, __) => Text(
                  formaterFcfa(valeur),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: TaamaColors.textOnDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChampDestination extends StatelessWidget {
  const _ChampDestination({required this.onTap, required this.onDicter});

  final VoidCallback onTap;
  final VoidCallback? onDicter;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Entrer une destination',
      child: Material(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TaamaRadius.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    size: 20, color: TaamaColors.primary),
                const SizedBox(width: TaamaSpacing.md),
                const Expanded(
                  child: Text(
                    'Entrer une destination',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: TaamaColors.textPrimary,
                    ),
                  ),
                ),
                if (onDicter != null)
                  Semantics(
                    button: true,
                    label: 'Dicter la destination',
                    child: InkWell(
                      onTap: onDicter,
                      borderRadius: BorderRadius.circular(TaamaRadius.sm),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.mic_none_rounded,
                            size: 20, color: TaamaColors.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PuceSuggestion extends StatelessWidget {
  const _PuceSuggestion({required this.suggestion, required this.onTap});

  final SuggestionDestination suggestion;
  final VoidCallback onTap;

  IconData get _icone => switch (suggestion.type) {
        TypeAdresse.domicile => Icons.home_rounded,
        TypeAdresse.travail => Icons.work_rounded,
        TypeAdresse.autre => Icons.place_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final avant = suggestion.miseEnAvant;
    final duree = suggestion.dureeMinutes;
    final texte = duree == null
        ? suggestion.libelle
        : '${suggestion.libelle} · $duree min';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TaamaRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: avant ? TaamaColors.primary : TaamaColors.navyLight,
          borderRadius: BorderRadius.circular(TaamaRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icone,
                size: 14,
                color: avant
                    ? TaamaColors.textOnDark
                    : TaamaColors.onNavyMuted),
            const SizedBox(width: 6),
            Text(
              texte,
              style: TextStyle(
                fontSize: 12,
                fontWeight: avant ? FontWeight.w700 : FontWeight.w500,
                color:
                    avant ? TaamaColors.textOnDark : TaamaColors.onNavyMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PuceAjout extends StatelessWidget {
  const _PuceAjout({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ajouter une adresse',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TaamaRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: TaamaColors.navyLight,
            borderRadius: BorderRadius.circular(TaamaRadius.pill),
          ),
          child: const Icon(Icons.add_rounded,
              size: 16, color: TaamaColors.onNavyMuted),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bande de confiance
// ---------------------------------------------------------------------------

class _BandeConfiance extends StatelessWidget {
  const _BandeConfiance();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icone, String texte) => Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 15, color: TaamaColors.success),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  texte,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: TaamaColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );

    return Container(
      color: TaamaColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          item(Icons.verified_user_rounded, 'Vérifiés'),
          item(Icons.sell_rounded, 'Prix fixe'),
          item(Icons.account_balance_wallet_rounded, 'Portefeuille'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bande carte + fiche du chauffeur le plus proche
// ---------------------------------------------------------------------------

class _BandeCarte extends StatelessWidget {
  const _BandeCarte({
    required this.positionClient,
    required this.conducteurs,
    required this.plusProche,
    required this.chargement,
    required this.onRecentrer,
  });

  final LatLng? positionClient;
  final List<ConducteurProche> conducteurs;
  final ConducteurProche? plusProche;
  final bool chargement;
  final VoidCallback onRecentrer;

  static const double hauteur = 172;

  @override
  Widget build(BuildContext context) {
    final centre = positionClient ?? const LatLng(12.6392, -8.0029); // Bamako

    return SizedBox(
      height: hauteur,
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: centre,
                initialZoom: 14.5,
                // Aperçu non interactif : la carte plein écran vient
                // à l'étape suivante du parcours.
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: TaamaMapTiles.clair,
                  subdomains: TaamaMapTiles.subdomains,
                  userAgentPackageName: TaamaMapTiles.userAgent,
                  maxNativeZoom: 19,
                ),
                attributionCarteTaama(),
                MarkerLayer(
                  markers: [
                    for (final c in conducteurs)
                      Marker(
                        point: c.position,
                        width: 26,
                        height: 26,
                        child: _MarqueurConducteur(estMoto: c.estMoto),
                      ),
                    if (positionClient != null)
                      Marker(
                        point: positionClient!,
                        width: 48,
                        height: 48,
                        child: const _PointClient(),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: _BoutonCarte(
              icone: Icons.my_location_rounded,
              semantique: 'Recentrer sur ma position',
              onTap: onRecentrer,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: _FicheConducteur(
              conducteur: plusProche,
              autres: conducteurs.length > 1 ? conducteurs.length - 1 : 0,
              chargement: chargement,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarqueurConducteur extends StatelessWidget {
  const _MarqueurConducteur({required this.estMoto});

  final bool estMoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TaamaColors.textPrimary,
        borderRadius: BorderRadius.circular(TaamaRadius.sm),
        boxShadow: TaamaShadows.card,
      ),
      child: Icon(
        estMoto ? Icons.two_wheeler_rounded : Icons.local_taxi_rounded,
        size: 16,
        color: TaamaColors.textOnDark,
      ),
    );
  }
}

/// Point du client avec halo pulsant. Respecte « réduire les animations ».
class _PointClient extends StatefulWidget {
  const _PointClient();

  @override
  State<_PointClient> createState() => _PointClientState();
}

class _PointClientState extends State<_PointClient>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const noyau = _NoyauPoint();
    if (MediaQuery.disableAnimationsOf(context)) return const Center(child: noyau);

    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final t = _ctrl.value;
            return Container(
              width: 20 + 26 * t,
              height: 20 + 26 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: TaamaColors.primary.withValues(alpha: 0.28 * (1 - t)),
              ),
            );
          },
        ),
        noyau,
      ],
    );
  }
}

class _NoyauPoint extends StatelessWidget {
  const _NoyauPoint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: TaamaColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: TaamaColors.surface, width: 3),
      ),
    );
  }
}

class _BoutonCarte extends StatelessWidget {
  const _BoutonCarte({
    required this.icone,
    required this.semantique,
    required this.onTap,
  });

  final IconData icone;
  final String semantique;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantique,
      child: Material(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TaamaRadius.md),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icone, size: 19, color: TaamaColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Fiche flottante : photo du chauffeur le plus proche, note, véhicule, délai.
class _FicheConducteur extends StatelessWidget {
  const _FicheConducteur({
    required this.conducteur,
    required this.autres,
    required this.chargement,
  });

  final ConducteurProche? conducteur;
  final int autres;
  final bool chargement;

  @override
  Widget build(BuildContext context) {
    final c = conducteur;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        boxShadow: TaamaShadows.floating,
      ),
      child: c == null
          ? Row(
              children: [
                Icon(
                  chargement
                      ? Icons.radar_rounded
                      : Icons.schedule_rounded,
                  size: 20,
                  color: TaamaColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    chargement
                        ? 'Recherche des chauffeurs autour de vous…'
                        : 'Aucun chauffeur autour de vous pour le moment.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: TaamaColors.textSecondary,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                PhotoAvatar(
                  nom: c.nomCourt,
                  urlPhoto: c.urlPhoto,
                  diametre: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${c.nomCourt} · le plus proche',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: TaamaColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          if (c.note != null) ...[
                            const Icon(Icons.star_rounded,
                                size: 13, color: TaamaColors.star),
                            const SizedBox(width: 2),
                            Text(
                              c.note!.toStringAsFixed(1).replaceAll('.', ','),
                              style: const TextStyle(
                                fontSize: 11,
                                color: TaamaColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              [
                                if (c.modeleVehicule != null) c.modeleVehicule!,
                                if (c.minutesAvant != null)
                                  'à ${c.minutesAvant} min',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: TaamaColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (autres > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: TaamaColors.successSoft,
                      borderRadius: BorderRadius.circular(TaamaRadius.sm),
                    ),
                    child: Text(
                      '+$autres autour',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: TaamaColors.success,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ligne de service avec prix plancher
// ---------------------------------------------------------------------------

class _LigneService extends StatefulWidget {
  const _LigneService({required this.service, required this.onTap});

  final ServiceCourse service;
  final VoidCallback onTap;

  @override
  State<_LigneService> createState() => _LigneServiceState();
}

class _LigneServiceState extends State<_LigneService> {
  bool _presse = false;

  IconData get _icone {
    final s = widget.service;
    if (s.code.toLowerCase().contains('moto')) return Icons.two_wheeler_rounded;
    if (s.climatise) return Icons.ac_unit_rounded;
    return Icons.directions_car_filled_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final avant = s.miseEnAvant;
    final actif = s.disponible;

    final fondIcone = s.climatise
        ? TaamaColors.warningSoft
        : (avant ? TaamaColors.primarySoft : TaamaColors.surfaceMuted);
    final couleurIcone = s.climatise
        ? TaamaColors.warning
        : (avant ? TaamaColors.primary : TaamaColors.textPrimary);

    final carte = Opacity(
      opacity: actif ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: TaamaColors.surface,
          borderRadius: BorderRadius.circular(TaamaRadius.lg),
          border: Border.all(
            color: avant ? TaamaColors.primary : TaamaColors.border,
            width: avant ? 2 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: fondIcone,
                borderRadius: BorderRadius.circular(TaamaRadius.md),
              ),
              child: Icon(_icone, size: 24, color: couleurIcone),
            ),
            const SizedBox(width: TaamaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          s.nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: TaamaColors.textPrimary,
                          ),
                        ),
                      ),
                      if (s.climatise) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: TaamaColors.warningSoft,
                            borderRadius:
                                BorderRadius.circular(TaamaRadius.sm),
                          ),
                          child: const Text(
                            'Climatisé',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: TaamaColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    actif ? s.argument : 'Indisponible pour le moment',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: TaamaColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: TaamaSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formaterFcfa(s.prixMinFcfa),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: TaamaColors.navy,
                  ),
                ),
                const Text(
                  'à partir de',
                  style: TextStyle(
                    fontSize: 11,
                    color: TaamaColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final contenu = avant
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              carte,
              Positioned(
                top: -9,
                left: 14,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: TaamaColors.primary,
                    borderRadius: BorderRadius.circular(TaamaRadius.sm),
                  ),
                  child: const Text(
                    'Le plus choisi',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: TaamaColors.textOnDark,
                    ),
                  ),
                ),
              ),
            ],
          )
        : carte;

    return Semantics(
      button: true,
      enabled: actif,
      label: '${s.nom}, ${s.argument}, à partir de '
          '${formaterFcfa(s.prixMinFcfa)}',
      child: GestureDetector(
        onTapDown: actif ? (_) => setState(() => _presse = true) : null,
        onTapUp: actif ? (_) => setState(() => _presse = false) : null,
        onTapCancel: actif ? () => setState(() => _presse = false) : null,
        onTap: actif ? widget.onTap : null,
        child: AnimatedScale(
          scale: _presse ? 0.98 : 1,
          duration: const Duration(milliseconds: 110),
          child: contenu,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions secondaires, dernière course, portefeuille
// ---------------------------------------------------------------------------

class _ActionSecondaire extends StatelessWidget {
  const _ActionSecondaire({
    required this.icone,
    required this.couleur,
    required this.libelle,
    required this.onTap,
  });

  final IconData icone;
  final Color couleur;
  final String libelle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.surface,
      borderRadius: BorderRadius.circular(TaamaRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TaamaRadius.lg),
            border: Border.all(color: TaamaColors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(icone, size: 20, color: couleur),
              const SizedBox(width: 10),
              Text(
                libelle,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: TaamaColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarteDerniereCourse extends StatelessWidget {
  const _CarteDerniereCourse({required this.course, required this.onTap});

  final DerniereCourse course;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TaamaColors.navy,
      borderRadius: BorderRadius.circular(TaamaRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: TaamaColors.primary,
                  borderRadius: BorderRadius.circular(TaamaRadius.md),
                ),
                child: const Icon(Icons.history_rounded,
                    size: 20, color: TaamaColors.textOnDark),
              ),
              const SizedBox(width: TaamaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Refaire votre dernière course',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: TaamaColors.textOnDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${course.depart} → ${course.arrivee} · '
                      '${formaterFcfa(course.prixFcfa)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: TaamaColors.onNavyMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  size: 20, color: TaamaColors.textOnDark),
            ],
          ),
        ),
      ),
    );
  }
}

class _BandeauPortefeuille extends StatelessWidget {
  const _BandeauPortefeuille({required this.onRecharger});

  final VoidCallback onRecharger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(TaamaSpacing.lg),
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        border: Border.all(color: TaamaColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Votre portefeuille est vide',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: TaamaColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Rechargez par Orange Money, Moov ou Wave.',
                  style: TextStyle(
                      fontSize: 12, color: TaamaColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: TaamaSpacing.md),
          FilledButton(
            onPressed: onRecharger,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('Recharger'),
          ),
        ],
      ),
    );
  }
}
