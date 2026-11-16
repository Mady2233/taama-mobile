import 'package:flutter/material.dart';

import '../../../theme/taama_theme.dart';
import '../../../utils/format.dart' show formaterFcfa;
import '../chauffeur_proche.dart';
import '../couleurs_recherche.dart';
import 'avatar_chauffeur.dart';

/// Panneau bas : liste des chauffeurs, fiche du sélectionné, bouton de choix.
class PanneauChauffeurs extends StatefulWidget {
  const PanneauChauffeurs({
    super.key,
    required this.chauffeurs,
    required this.selectionne,
    required this.chargement,
    required this.erreur,
    required this.obsolete,
    required this.rayonM,
    required this.onSelection,
    required this.onChoisir,
    required this.onReessayer,
    this.prix,
    this.onPlusProche,
    this.choixBloque = false,
  });

  /// Chauffeurs filtrés, du plus proche au plus éloigné.
  final List<ChauffeurProche> chauffeurs;
  final ChauffeurProche? selectionne;
  final bool chargement;
  final String? erreur;

  /// Positions périmées : le choix est bloqué (fail-closed).
  final bool obsolete;
  final int rayonM;
  final ValueChanged<ChauffeurProche> onSelection;
  final Future<void> Function(ChauffeurProche chauffeur) onChoisir;
  final VoidCallback onReessayer;

  /// Prix de la course, le même quel que soit le chauffeur : rappelé sur
  /// « Le plus proche ». Null : non affiché.
  final int? prix;

  /// « Le plus proche » : commander sans choisir, au même prix. Toujours
  /// visible, même sans chauffeur à l'écran. Null : bouton absent.
  final VoidCallback? onPlusProche;

  /// Choix impossible pour l'instant (plafond du serveur atteint) : seul
  /// « Le plus proche » reste, mis en avant.
  final bool choixBloque;

  @override
  State<PanneauChauffeurs> createState() => _PanneauChauffeursState();
}

class _PanneauChauffeursState extends State<PanneauChauffeurs> {
  static const _largeurElement = 64.0;
  static const _espacement = 12.0;

  final _defilement = ScrollController();
  bool _envoi = false;

  @override
  void didUpdateWidget(covariant PanneauChauffeurs ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.selectionne?.id != widget.selectionne?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _amenerEnVue());
    }
  }

  @override
  void dispose() {
    _defilement.dispose();
    super.dispose();
  }

  /// Fait défiler la liste pour centrer le chauffeur choisi sur le radar.
  void _amenerEnVue() {
    if (!mounted || !_defilement.hasClients) return;
    final index =
        widget.chauffeurs.indexWhere((c) => c.id == widget.selectionne?.id);
    if (index < 0) return;
    final position = _defilement.position;
    final cible = index * (_largeurElement + _espacement) -
        (position.viewportDimension - _largeurElement) / 2;
    _defilement.animateTo(
      cible.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble(),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _choisir(ChauffeurProche chauffeur) async {
    if (_envoi) return; // anti double appui
    setState(() => _envoi = true);
    try {
      await widget.onChoisir(chauffeur);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final basSysteme = MediaQuery.of(context).padding.bottom;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CouleursRecherche.panneau,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: CouleursRecherche.ombrePanneau, blurRadius: 24, offset: Offset(0, -4)),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + basSysteme),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Poignee(),
              const SizedBox(height: 14),
              ..._contenu(context),
              if (widget.onPlusProche != null) ...[
                const SizedBox(height: 6),
                _BoutonPlusProche(
                  prix: widget.prix,
                  enAvant: widget.choixBloque,
                  onTap: _envoi ? null : widget.onPlusProche,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _contenu(BuildContext context) {
    final chauffeurs = widget.chauffeurs;
    final selection = widget.selectionne;

    if (chauffeurs.isEmpty) {
      if (widget.chargement) return const [_Squelette()];
      final erreur = widget.erreur;
      return [
        _EtatVide(
          titre: erreur ??
              'Aucun chauffeur dans un rayon de ${formaterRayon(widget.rayonM)}',
          detail: erreur == null
              ? 'De nouveaux chauffeurs se connectent régulièrement. '
                  'Réessaie dans un instant.'
              : null,
          enErreur: erreur != null,
          onReessayer: widget.onReessayer,
        ),
      ];
    }

    final hauteurListe = 70 + MediaQuery.textScalerOf(context).scale(18);
    return [
      _EnTetePanneau(nombre: chauffeurs.length),
      const SizedBox(height: 14),
      SizedBox(
        height: hauteurListe,
        child: ListView.separated(
          controller: _defilement,
          scrollDirection: Axis.horizontal,
          itemCount: chauffeurs.length,
          separatorBuilder: (_, __) => const SizedBox(width: _espacement),
          itemBuilder: (context, index) {
            final chauffeur = chauffeurs[index];
            return _ElementListe(
              chauffeur: chauffeur,
              selectionne: chauffeur.id == selection?.id,
              largeur: _largeurElement,
              onTap: () => widget.onSelection(chauffeur),
            );
          },
        ),
      ),
      const SizedBox(height: 12),
      if (selection != null) _FicheChauffeur(chauffeur: selection),
      const SizedBox(height: 14),
      _BoutonPrincipal(
        libelle: widget.choixBloque
            ? 'Choix indisponible pour l’instant'
            : selection == null
                ? 'Choisir un chauffeur'
                : widget.obsolete
                    ? 'Mise à jour des positions…'
                    : 'Choisir ${selection.prenom}',
        icone: Icons.arrow_forward_rounded,
        envoi: _envoi,
        onPressed: selection == null || widget.obsolete || widget.choixBloque
            ? null
            : () => _choisir(selection),
      ),
    ];
  }
}

class _Poignee extends StatelessWidget {
  const _Poignee();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: CouleursRecherche.poignee,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _EnTetePanneau extends StatelessWidget {
  const _EnTetePanneau({required this.nombre});

  final int nombre;

  @override
  Widget build(BuildContext context) {
    final titre = nombre == 1
        ? '1 chauffeur à proximité'
        : '$nombre chauffeurs à proximité';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            titre,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: CouleursRecherche.texte,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const SizedBox(
          width: 112,
          child: Padding(
            padding: EdgeInsets.only(top: 3),
            child: Text(
              'Les plus proches d’abord',
              style: TextStyle(
                fontSize: 13,
                color: CouleursRecherche.texteDoux,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ElementListe extends StatelessWidget {
  const _ElementListe({
    required this.chauffeur,
    required this.selectionne,
    required this.largeur,
    required this.onTap,
  });

  final ChauffeurProche chauffeur;
  final bool selectionne;
  final double largeur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selectionne,
      label: '${chauffeur.nomAffiche}, ${chauffeur.etaMin} min',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: largeur,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selectionne
                        ? CouleursRecherche.indigo
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: AvatarChauffeur(
                  graine: chauffeur.id,
                  initiales: chauffeur.initiales,
                  estMoto: chauffeur.typeVehicule == TypeVehicule.moto,
                  taille: 52,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${chauffeur.etaMin} min',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selectionne ? FontWeight.w700 : FontWeight.w500,
                  color: selectionne
                      ? CouleursRecherche.indigo
                      : CouleursRecherche.texteDoux,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FicheChauffeur extends StatelessWidget {
  const _FicheChauffeur({required this.chauffeur});

  final ChauffeurProche chauffeur;

  @override
  Widget build(BuildContext context) {
    final c = chauffeur;
    final note = c.note;
    final details = [
      if (c.modeleVehicule.isNotEmpty) c.modeleVehicule,
      if (c.couleurVehicule.isNotEmpty) c.couleurVehicule,
    ].join(' · ');

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(c.id),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CouleursRecherche.bordure),
        ),
        child: Row(
          children: [
            AvatarChauffeur(
              graine: c.id,
              initiales: c.initiales,
              estMoto: c.typeVehicule == TypeVehicule.moto,
              taille: 56,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.nomAffiche,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: CouleursRecherche.texte,
                          ),
                        ),
                      ),
                      if (c.verifie) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 17,
                          color: CouleursRecherche.indigo,
                          semanticLabel: 'Chauffeur vérifié',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 17, color: CouleursRecherche.ambre),
                      const SizedBox(width: 3),
                      Text(
                        note == null ? 'Nouveau' : formaterNote(note),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: CouleursRecherche.texte,
                        ),
                      ),
                      if (details.isNotEmpty)
                        Flexible(
                          child: Text(
                            ' · $details',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: CouleursRecherche.texteDoux,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: CouleursRecherche.indigoPale,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      formaterTarifKm(c.tarifKm),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: CouleursRecherche.indigo,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${c.etaMin} min',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: CouleursRecherche.indigo,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formaterDistance(c.distanceM),
                  style: const TextStyle(
                    fontSize: 13,
                    color: CouleursRecherche.texteDoux,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BoutonPrincipal extends StatelessWidget {
  const _BoutonPrincipal({
    required this.libelle,
    required this.onPressed,
    this.icone,
    this.envoi = false,
  });

  final String libelle;
  final VoidCallback? onPressed;
  final IconData? icone;
  final bool envoi;

  @override
  Widget build(BuildContext context) {
    final icone = this.icone;
    return SizedBox(
      height: 58,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: CouleursRecherche.indigo,
          foregroundColor: Colors.white,
          disabledBackgroundColor: CouleursRecherche.indigoDesactive,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          // Police explicite : ce style remplace celui hérité du thème.
          textStyle: const TextStyle(
            fontFamily: TaamaFonts.body,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: envoi
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      libelle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (icone != null) ...[
                    const SizedBox(width: 10),
                    Icon(icone, size: 22),
                  ],
                ],
              ),
      ),
    );
  }
}

/// « Le plus proche » : commander sans choisir, au même prix. Discret, sauf
/// quand le choix est bloqué : il devient alors le bouton principal.
class _BoutonPlusProche extends StatelessWidget {
  const _BoutonPlusProche({required this.prix, required this.enAvant, required this.onTap});

  final int? prix;
  final bool enAvant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final prix = this.prix;
    final libelle = prix == null ? 'Le plus proche' : 'Le plus proche · ${formaterFcfa(prix)}';
    const style = TextStyle(fontFamily: TaamaFonts.body, fontSize: 16, fontWeight: FontWeight.w700);
    final texte = Text(libelle, maxLines: 1, overflow: TextOverflow.ellipsis);
    return SizedBox(
      height: 52,
      child: enAvant
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: CouleursRecherche.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: style,
              ),
              child: texte,
            )
          : TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: CouleursRecherche.indigo,
                textStyle: style,
              ),
              child: texte,
            ),
    );
  }
}

class _Squelette extends StatelessWidget {
  const _Squelette();

  static const _gris = CouleursRecherche.gris;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Recherche des chauffeurs…',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: CouleursRecherche.texte,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 82,
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            scrollDirection: Axis.horizontal,
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) => const SizedBox(
              width: 64,
              child: Column(
                children: [
                  CircleAvatar(radius: 29, backgroundColor: _gris),
                  SizedBox(height: 8),
                  SizedBox(
                    width: 36,
                    height: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _gris,
                        borderRadius: BorderRadius.all(Radius.circular(5)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(
          height: 96,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: CouleursRecherche.grisClair,
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _BoutonPrincipal(libelle: 'Recherche en cours…', onPressed: null),
      ],
    );
  }
}

class _EtatVide extends StatelessWidget {
  const _EtatVide({
    required this.titre,
    required this.detail,
    required this.enErreur,
    required this.onReessayer,
  });

  final String titre;
  final String? detail;
  final bool enErreur;
  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: CouleursRecherche.indigoPale,
              ),
              child: Icon(
                enErreur ? Icons.wifi_off_rounded : Icons.radar,
                color: CouleursRecherche.indigo,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: CouleursRecherche.texte,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 14,
                        color: CouleursRecherche.texteDoux,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _BoutonPrincipal(
          libelle: enErreur ? 'Réessayer' : 'Actualiser',
          icone: Icons.refresh_rounded,
          onPressed: onReessayer,
        ),
      ],
    );
  }
}
