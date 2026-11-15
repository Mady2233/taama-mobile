import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/taama_theme.dart';
import 'chauffeur_proche.dart';
import 'chauffeurs_proches_repository.dart';
import 'couleurs_recherche.dart';
import 'recherche_chauffeur_controller.dart';
import 'widgets/carte_chauffeurs.dart';
import 'widgets/panneau_chauffeurs.dart';

/// Ce que la page a fait du chauffeur choisi.
enum IssueChoix {
  /// La page quitte l'écran (demande envoyée, ou autre suite) : rien à faire.
  quitte,

  /// Ce chauffeur n'est plus disponible : la recherche repart tout de suite.
  autreChauffeur,

  /// Plafond de choix atteint : choix bloqué, « Le plus proche » en avant.
  limiteAtteinte,

  /// Autre erreur, déjà affichée par la page : la recherche repart.
  erreur,
}

/// Écran « Choisis ton chauffeur » : les chauffeurs proches en direct sur la
/// vraie carte, du type du service choisi, et le choix manuel par le client.
class RechercheChauffeurScreen extends StatefulWidget {
  const RechercheChauffeurScreen({
    super.key,
    required this.repository,
    required this.positionDepart,
    required this.onChauffeurChoisi,
    this.type,
    this.prix,
    this.onPlusProche,
    this.onFonctionCoupee,
    this.rayonM = 3000,
  }) : assert(rayonM > 0 && rayonM <= 5000);

  final ChauffeursProchesRepository repository;

  /// Point de prise en charge du devis : centre de la carte et de la
  /// recherche. Le serveur cherche le chauffeur choisi autour de ce point :
  /// pas de « Me localiser » sur cet écran.
  final GeoPoint positionDepart;

  /// Type du service choisi (le serveur ne retrouve un chauffeur choisi que
  /// parmi ceux du type du devis) ; null : tous les types.
  final TypeVehicule? type;

  /// Appelé quand le client confirme son choix. Gère ses propres erreurs
  /// (messages compris) et dit à l'écran quoi faire ensuite. Le
  /// rafraîchissement est suspendu pendant l'appel.
  final Future<IssueChoix> Function(ChauffeurProche chauffeur) onChauffeurChoisi;

  /// Prix de la course, le même quel que soit le chauffeur.
  final int? prix;

  /// « Le plus proche », au même prix. Null : bouton absent.
  final VoidCallback? onPlusProche;

  /// Le serveur a coupé le choix du chauffeur (404) : appelé une fois.
  final VoidCallback? onFonctionCoupee;

  final int rayonM;

  @override
  State<RechercheChauffeurScreen> createState() =>
      _RechercheChauffeurScreenState();
}

class _RechercheChauffeurScreenState extends State<RechercheChauffeurScreen>
    with WidgetsBindingObserver {
  late final RechercheChauffeurController _controleur =
      RechercheChauffeurController(
    repository: widget.repository,
    position: widget.positionDepart,
    type: widget.type,
    rayonDemande: widget.rayonM,
  );

  /// Hauteur de carte qui passe sous le panneau (ses coins arrondis laissent
  /// voir la carte, pas un fond vide).
  static const double _sousLePanneau = 28;

  bool _choixEnCours = false;
  bool _choixBloque = false;
  bool _coupureSignalee = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controleur.demarrer();
  }

  /// Aucune requête quand l'app est en arrière-plan (data et batterie).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_choixEnCours) _controleur.demarrer();
    } else {
      _controleur.suspendre();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controleur.dispose();
    super.dispose();
  }

  Future<void> _choisir(ChauffeurProche chauffeur) async {
    if (_choixEnCours) return;
    _choixEnCours = true;
    _controleur.suspendre();
    var issue = IssueChoix.erreur;
    try {
      issue = await widget.onChauffeurChoisi(chauffeur);
    } finally {
      _choixEnCours = false;
      if (mounted && issue != IssueChoix.quitte) {
        if (issue == IssueChoix.limiteAtteinte) setState(() => _choixBloque = true);
        _controleur.demarrer();
      }
    }
  }

  /// Fonction coupée sur le serveur : la page est prévenue une seule fois.
  void _signalerCoupure() {
    if (_coupureSignalee) return;
    _coupureSignalee = true;
    final rappel = widget.onFonctionCoupee;
    if (rappel == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) rappel();
    });
  }

  void _selectionner(ChauffeurProche chauffeur) {
    unawaited(HapticFeedback.selectionClick());
    _controleur.selectionner(chauffeur);
  }

  @override
  Widget build(BuildContext context) {
    final nuit = Theme.of(context).brightness == Brightness.dark;
    final hautSysteme = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: nuit ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: nuit ? TaamaColors.mapNight : TaamaColors.mapPlaceholder,
        body: ListenableBuilder(
          listenable: _controleur,
          builder: (context, _) {
            final c = _controleur;
            final selection = c.selectionne;
            if (c.fonctionCoupee) _signalerCoupure();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        right: 0,
                        bottom: -_sousLePanneau,
                        child: CarteChauffeurs(
                          chauffeurs: c.chauffeursFiltres,
                          selectionne: selection,
                          centre: widget.positionDepart,
                          rayonM: c.rayonM,
                          nuit: nuit,
                          onSelection: _selectionner,
                          // En-tête (≈ 76 px sous la barre d'état, plus
                          // avec un texte agrandi) et bas de carte caché par
                          // le panneau.
                          marges: EdgeInsets.only(
                            top: hautSysteme + MediaQuery.textScalerOf(context).scale(76),
                            bottom: _sousLePanneau,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        right: 0,
                        child: SafeArea(
                          bottom: false,
                          child: _EnTete(
                            rayonM: c.rayonM,
                            chargement: c.chargementInitial,
                            obsolete: c.estObsolete,
                            nuit: nuit,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                PanneauChauffeurs(
                  chauffeurs: c.chauffeursFiltres,
                  selectionne: selection,
                  chargement: c.chargementInitial,
                  erreur: c.erreur,
                  obsolete: c.estObsolete,
                  rayonM: c.rayonM,
                  onSelection: _selectionner,
                  onChoisir: _choisir,
                  onReessayer: _controleur.demarrer,
                  prix: widget.prix,
                  onPlusProche: widget.onPlusProche,
                  choixBloque: _choixBloque,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.rayonM,
    required this.chargement,
    required this.obsolete,
    required this.nuit,
  });

  final int rayonM;
  final bool chargement;
  final bool obsolete;
  final bool nuit;

  @override
  Widget build(BuildContext context) {
    final rayon = formaterRayon(rayonM);
    final enAlerte = obsolete && !chargement;
    final statut = chargement
        ? 'Recherche · rayon $rayon'
        : enAlerte
            ? 'Connexion instable · nouvelle tentative'
            : 'En direct · rayon $rayon';
    final texte = nuit ? TaamaColors.textOnDark : TaamaColors.textPrimary;
    final texteDoux = nuit ? TaamaColors.onNightMuted : TaamaColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: nuit ? TaamaColors.night : TaamaColors.surface,
        elevation: 4,
        shadowColor: TaamaColors.ombreMarqueur,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          child: Row(
            children: [
              _BoutonRetour(
                couleur: texte,
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Choisis ton chauffeur',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: texte,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _PointDirect(
                          couleur: enAlerte
                              ? CouleursRecherche.alerte
                              : TaamaColors.accentMint,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            statut,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: texteDoux, fontSize: 13),
                          ),
                        ),
                      ],
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

class _BoutonRetour extends StatelessWidget {
  const _BoutonRetour({required this.couleur, required this.onTap});

  final Color couleur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Retour',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(Icons.arrow_back_ios_new_rounded, color: couleur, size: 18),
          ),
        ),
      ),
    );
  }
}

class _PointDirect extends StatelessWidget {
  const _PointDirect({required this.couleur});

  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: couleur,
        boxShadow: [BoxShadow(color: couleur.withValues(alpha: 0.55), blurRadius: 6)],
      ),
    );
  }
}
