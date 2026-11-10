// lib/widgets/decision_demande.dart
//
// Demande entrante : le prix (l'offre du client, ou le prix de la course) et
// les décisions du chauffeur — accepter, refuser, contre-proposer. Le − et le +
// n'apparaissent qu'après « Contre-proposer » (SelecteurPrix dans l'écran).
// Présentationnel : montants et actions par paramètres.

import 'package:flutter/material.dart';

import '../theme/couleurs_taama.dart';
import '../utils/format.dart';

/// Mode de paiement de la course.
class PastilleEspeces extends StatelessWidget {
  const PastilleEspeces({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.payments_rounded, size: 16, color: Colors.green.shade700),
          const SizedBox(width: 4),
          Text(
            'Espèces',
            style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Le prix que le chauffeur encaissera en acceptant. Offre du client : avec
/// le prix standard et l'écart, pour comparer d'un coup d'œil. Contre-
/// proposition envoyée : « Ta contre-proposition », avec ce que le client
/// proposait (ou le prix standard) en dessous.
class BlocPrixDemande extends StatelessWidget {
  const BlocPrixDemande({
    super.key,
    required this.prix,
    this.prixStandard,
    this.prixOffert,
    this.reduction = 0,
    this.contreProposition = false,
  });

  /// Montant encaissé (promo déduite) ; null : « — », jamais inventé.
  final int? prix;

  /// Avant promo : présents seulement si le client a offert un autre prix.
  final int? prixStandard;
  final int? prixOffert;

  /// Promo du client, déjà retirée de [prix] : retirée aussi du standard et
  /// de l'offre affichés en comparaison, pour comparer des montants
  /// comparables.
  final int reduction;

  /// [prix] est celui que le chauffeur a proposé au client, pas son offre.
  final bool contreProposition;

  String _apresPromo(int montant) => formaterFcfa(montant - reduction < 0 ? 0 : montant - reduction);

  bool get _offre => prixOffert != null && prixStandard != null && prixOffert != prixStandard;

  String get _titre {
    if (contreProposition) return 'Ta contre-proposition';
    return _offre ? 'Le client propose' : 'Prix de la course';
  }

  /// Sous une contre-proposition : ce que le client proposait, sinon le prix
  /// standard ; null si inconnu (rien n'est affiché).
  String? get _rappel {
    if (_offre) return 'Le client proposait ${_apresPromo(prixOffert!)}';
    final standard = prixStandard;
    return standard == null ? null : 'Standard ${_apresPromo(standard)}';
  }

  static const TextStyle _stylePrix = TextStyle(
    color: CouleursTaama.terreCuite,
    fontWeight: FontWeight.w900,
    fontSize: 38,
    height: 1,
  );

  @override
  Widget build(BuildContext context) {
    final reduit = MediaQuery.disableAnimationsOf(context);
    final valeur = prix;
    final ecart = _offre ? prixOffert! - prixStandard! : 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: CouleursTaama.sable,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: CouleursTaama.grisTexte, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              const PastilleEspeces(),
            ],
          ),
          const SizedBox(height: 6),
          valeur == null
              ? const Text('—', style: _stylePrix)
              : TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduit ? valeur.toDouble() : 0, end: valeur.toDouble()),
                  duration: reduit ? Duration.zero : const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(formaterFcfa(v.round()), style: _stylePrix),
                  ),
                ),
          if (contreProposition && _rappel != null) ...[
            const SizedBox(height: 8),
            Text(
              _rappel!,
              style: const TextStyle(color: CouleursTaama.grisTexte, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ] else if (!contreProposition && _offre) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Standard ${_apresPromo(prixStandard!)}',
                  style: const TextStyle(color: CouleursTaama.grisTexte, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (ecart < 0 ? CouleursTaama.indigo : CouleursTaama.terreCuite).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${ecart > 0 ? '+' : '−'}${formaterFcfa(ecart.abs())}',
                    style: TextStyle(
                      color: ecart < 0 ? CouleursTaama.indigo : CouleursTaama.terreCuite,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Boutons de la demande. Vue de départ : « Accepter · prix », « Refuser » et
/// « Contre-proposer » (seulement si le serveur a envoyé les limites).
/// Contre-proposition ouverte : « Proposer ce prix » (actif dès que le prix a
/// changé) et « Annuler ».
class ActionsDemande extends StatelessWidget {
  const ActionsDemande({
    super.key,
    required this.prix,
    required this.contrePossible,
    required this.modeContre,
    required this.prixModifie,
    required this.enTraitement,
    required this.envoiEnCours,
    required this.onAccepter,
    required this.onRefuser,
    required this.onContreProposer,
    required this.onProposer,
    required this.onAnnulerContre,
    this.pulse,
  });

  /// Montant encaissé en acceptant (promo déduite).
  final int? prix;
  final bool contrePossible;
  final bool modeContre;
  final bool prixModifie;

  /// Une réponse part : plus aucun bouton actif.
  final bool enTraitement;

  /// C'est l'acceptation (ou la contre-proposition) qui part : son bouton
  /// tourne ; sinon c'est le refus.
  final bool envoiEnCours;
  final VoidCallback onAccepter;
  final VoidCallback onRefuser;
  final VoidCallback onContreProposer;
  final VoidCallback onProposer;
  final VoidCallback onAnnulerContre;

  /// Halo qui respire autour d'« Accepter » ; null : immobile.
  final Animation<double>? pulse;

  static final ButtonStyle _contour = OutlinedButton.styleFrom(
    minimumSize: const Size(0, 54),
    foregroundColor: CouleursTaama.indigo,
    side: BorderSide(color: CouleursTaama.indigo.withValues(alpha: 0.25), width: 1.5),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  );

  static const TextStyle _texteContour = TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5);

  @override
  Widget build(BuildContext context) {
    return modeContre ? _contre() : _depart();
  }

  Widget _depart() {
    final accepter = _BoutonPrincipal(
      couleur: CouleursTaama.terreCuite,
      icone: Icons.check_circle_rounded,
      texte: prix != null ? 'Accepter · ${formaterFcfa(prix!)}' : 'Accepter',
      enCours: enTraitement && envoiEnCours,
      onPressed: enTraitement ? null : onAccepter,
    );
    final halo = pulse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (halo == null)
          accepter
        else
          AnimatedBuilder(
            animation: halo,
            builder: (context, child) {
              final t = enTraitement ? 0.0 : halo.value;
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: CouleursTaama.terreCuite.withValues(alpha: 0.40 * (1 - t)),
                      blurRadius: 6 + 18 * t,
                      spreadRadius: 6 * t,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: accepter,
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: enTraitement ? null : onRefuser,
                style: _contour,
                child: enTraitement && !envoiEnCours
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: CouleursTaama.indigo),
                      )
                    : const Text('Refuser', style: _texteContour),
              ),
            ),
            if (contrePossible) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enTraitement ? null : onContreProposer,
                  style: _contour,
                  icon: const Icon(Icons.swap_vert_rounded, size: 20),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Contre-proposer', style: _texteContour)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _contre() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BoutonPrincipal(
          couleur: CouleursTaama.indigo,
          icone: Icons.send_rounded,
          texte: 'Proposer ce prix',
          enCours: enTraitement && envoiEnCours,
          onPressed: enTraitement || !prixModifie ? null : onProposer,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: enTraitement ? null : onAnnulerContre,
          style: TextButton.styleFrom(
            foregroundColor: CouleursTaama.grisTexte,
            minimumSize: const Size(0, 48),
          ),
          child: const Text('Annuler', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ],
    );
  }
}

class _BoutonPrincipal extends StatelessWidget {
  const _BoutonPrincipal({
    required this.couleur,
    required this.icone,
    required this.texte,
    required this.enCours,
    required this.onPressed,
  });

  final Color couleur;
  final IconData icone;
  final String texte;
  final bool enCours;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: couleur,
          disabledBackgroundColor: couleur.withValues(alpha: 0.45),
          foregroundColor: CouleursTaama.blanc,
          disabledForegroundColor: CouleursTaama.blanc,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: enCours
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: CouleursTaama.blanc),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icone, size: 24),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(texte, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
