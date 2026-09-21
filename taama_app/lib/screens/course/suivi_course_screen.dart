// lib/screens/course/suivi_course_screen.dart
//
// Écran unique de suivi d'une course, piloté par le statut :
//   recherche → acceptee → enRoute → aBord → terminee
// La carte reste montée d'un bout à l'autre : pas de navigation entre
// les étapes, donc aucune transition brutale ni rechargement de tuiles.
//
// Corrections de la v1 :
//  - l'état `terminee` existe enfin (paiement + notation) : le parcours
//    ne se termine plus sans encaisser ni noter le chauffeur ;
//  - le parent passe son propre MapController via `mapController` et
//    recentre lui-même — plus de bouton qui ne déplace rien ;
//  - `onSos`, `onPartager`, `onRecentrer`, `onAppeler`, `onMessage` sont
//    nullables : un bouton non câblé n'est pas affiché, jamais
//    affiché-mais-inerte.
//
// Widget présentationnel : données par paramètres, actions par callbacks.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/taama_theme.dart';
import '../../utils/format.dart';
import '../../widgets/photo_avatar.dart';
import '../../widgets/taama_map.dart';

enum StatutCourse { recherche, acceptee, enRoute, aBord, terminee }

enum MoyenPaiement { portefeuille, especes }

class ChauffeurCourse {
  const ChauffeurCourse({
    required this.nomCourt,
    required this.plaque,
    this.urlPhoto,
    this.note,
    this.nombreCourses,
    this.vehicule,
    this.couleurVehicule,
  });

  final String nomCourt;
  final String plaque;
  final String? urlPhoto;
  final double? note;
  final int? nombreCourses;

  /// Ex. « Corolla ». La couleur est passée à part.
  final String? vehicule;

  /// Résultat de `couleurVehicule()` (utils/format.dart). Null → aucune
  /// pastille : mieux qu'une couleur devinée, qui ferait chercher la
  /// mauvaise voiture au client.
  final Color? couleurVehicule;
}

class SuiviCourseScreen extends StatelessWidget {
  const SuiviCourseScreen({
    super.key,
    required this.statut,
    required this.depart,
    required this.arrivee,
    required this.prixFcfa,
    required this.soldeFcfa,
    required this.onRetour,
    required this.onAnnuler,
    this.mapController,
    this.chauffeur,
    this.positionClient,
    this.positionDestination,
    this.positionChauffeur,
    this.itineraire = const [],
    this.minutesAvantArrivee,
    this.distanceKm,
    this.phraseSituation,
    this.onSos,
    this.onPartager,
    this.onRecentrer,
    this.onAppeler,
    this.onMessage,
    this.paiementEnCours = false,
    this.dejaPayee = false,
    this.onPayer,
    this.noteEnCours = false,
    this.dejaNotee = false,
    this.onNoter,
    this.onTerminer,
  });

  final StatutCourse statut;
  final ChauffeurCourse? chauffeur;

  /// Passé tel quel à [TaamaMap] : c'est par lui que le parent recentre
  /// (`controller.move(position, 15.5)` dans son propre onRecentrer).
  final MapController? mapController;

  final String depart;
  final String arrivee;
  final int prixFcfa;
  final int soldeFcfa;

  final LatLng? positionClient;
  final LatLng? positionDestination;
  final LatLng? positionChauffeur;
  final List<LatLng> itineraire;

  final int? minutesAvantArrivee;
  final double? distanceKm;

  /// Phrase calculée serveur (« … vient de tourner sur votre rue »).
  /// Null → ligne non affichée : jamais de texte inventé côté app.
  final String? phraseSituation;

  final VoidCallback onRetour;
  final VoidCallback onAnnuler;

  /// Chaque callback null masque son bouton.
  final VoidCallback? onSos;
  final VoidCallback? onPartager;
  final VoidCallback? onRecentrer;
  final VoidCallback? onAppeler;
  final VoidCallback? onMessage;

  // Fin de course
  final bool paiementEnCours;
  final bool dejaPayee;
  final ValueChanged<MoyenPaiement>? onPayer;
  final bool noteEnCours;
  final bool dejaNotee;

  /// (étoiles 1-5, commentaire éventuel)
  final void Function(int etoiles, String? commentaire)? onNoter;

  /// Quitter l'écran une fois payée et notée.
  final VoidCallback? onTerminer;

  bool get _terminee => statut == StatutCourse.terminee;

  bool get _annulable =>
      statut == StatutCourse.recherche ||
      statut == StatutCourse.acceptee ||
      statut == StatutCourse.enRoute;

  @override
  Widget build(BuildContext context) {
    final hauteur = MediaQuery.sizeOf(context).height;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: TaamaColors.night,
        body: Stack(
          children: [
            Positioned.fill(
              child: TaamaMap(
                controller: mapController,
                positionClient: positionClient,
                destination: statut == StatutCourse.aBord || _terminee
                    ? positionDestination
                    : null,
                vehicules: [
                  if (positionChauffeur != null && !_terminee)
                    VehiculeCarte(
                      id: 'course',
                      position: positionChauffeur!,
                      miseEnAvant: true,
                    ),
                ],
                itineraire: itineraire,
                themeNuit: true,
                margeCadrage: const EdgeInsets.fromLTRB(56, 110, 56, 320),
              ),
            ),
            _BarreHaute(
              onRetour: onRetour,
              onPartager: _terminee ? null : onPartager,
              onSos: _terminee ? null : onSos,
            ),
            if (phraseSituation != null && !_terminee)
              Positioned(
                left: 14,
                bottom: hauteur * 0.46,
                child: _PhraseSituation(texte: phraseSituation!),
              ),
            if (onRecentrer != null)
              Positioned(
                right: 14,
                bottom: hauteur * 0.45,
                child: _BoutonCarte(
                  icone: Icons.my_location_rounded,
                  semantique: 'Recentrer sur ma position',
                  onTap: onRecentrer!,
                ),
              ),
            DraggableScrollableSheet(
              initialChildSize: _terminee ? 0.62 : 0.46,
              minChildSize: 0.22,
              maxChildSize: 0.92,
              builder: (context, scroll) => _Feuille(
                controleur: scroll,
                statut: statut,
                chauffeur: chauffeur,
                depart: depart,
                arrivee: arrivee,
                prixFcfa: prixFcfa,
                soldeFcfa: soldeFcfa,
                minutesAvantArrivee: minutesAvantArrivee,
                distanceKm: distanceKm,
                annulable: _annulable,
                onAppeler: onAppeler,
                onMessage: onMessage,
                onAnnuler: onAnnuler,
                paiementEnCours: paiementEnCours,
                dejaPayee: dejaPayee,
                onPayer: onPayer,
                noteEnCours: noteEnCours,
                dejaNotee: dejaNotee,
                onNoter: onNoter,
                onTerminer: onTerminer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Barre haute flottante
// ---------------------------------------------------------------------------

class _BarreHaute extends StatelessWidget {
  const _BarreHaute({
    required this.onRetour,
    required this.onPartager,
    required this.onSos,
  });

  final VoidCallback onRetour;
  final VoidCallback? onPartager;
  final VoidCallback? onSos;

  @override
  Widget build(BuildContext context) {
    final haut = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: haut + 12,
      left: 14,
      right: 14,
      child: Row(
        children: [
          _BoutonCarte(
            icone: Icons.chevron_left_rounded,
            semantique: 'Retour',
            onTap: onRetour,
          ),
          const Spacer(),
          if (onPartager != null) ...[
            _BoutonCarte(
              icone: Icons.ios_share_rounded,
              semantique: 'Partager le suivi de ma course',
              onTap: onPartager!,
            ),
            const SizedBox(width: 8),
          ],
          if (onSos != null)
            _BoutonCarte(
              icone: Icons.emergency_rounded,
              semantique: 'Alerte d’urgence',
              onTap: onSos!,
              fond: TaamaColors.dangerNightBg,
              couleurIcone: TaamaColors.dangerNight,
            ),
        ],
      ),
    );
  }
}

class _BoutonCarte extends StatelessWidget {
  const _BoutonCarte({
    required this.icone,
    required this.semantique,
    required this.onTap,
    this.fond = TaamaColors.nightControl,
    this.couleurIcone = TaamaColors.textOnDark,
  });

  final IconData icone;
  final String semantique;
  final VoidCallback onTap;
  final Color fond;
  final Color couleurIcone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantique,
      child: Material(
        color: fond,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TaamaRadius.lg),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icone, size: 21, color: couleurIcone),
          ),
        ),
      ),
    );
  }
}

class _PhraseSituation extends StatelessWidget {
  const _PhraseSituation({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: TaamaColors.night.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(TaamaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: TaamaColors.accentMint,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              texte,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: TaamaColors.textOnDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feuille glissante
// ---------------------------------------------------------------------------

class _Feuille extends StatelessWidget {
  const _Feuille({
    required this.controleur,
    required this.statut,
    required this.chauffeur,
    required this.depart,
    required this.arrivee,
    required this.prixFcfa,
    required this.soldeFcfa,
    required this.minutesAvantArrivee,
    required this.distanceKm,
    required this.annulable,
    required this.onAppeler,
    required this.onMessage,
    required this.onAnnuler,
    required this.paiementEnCours,
    required this.dejaPayee,
    required this.onPayer,
    required this.noteEnCours,
    required this.dejaNotee,
    required this.onNoter,
    required this.onTerminer,
  });

  final ScrollController controleur;
  final StatutCourse statut;
  final ChauffeurCourse? chauffeur;
  final String depart;
  final String arrivee;
  final int prixFcfa;
  final int soldeFcfa;
  final int? minutesAvantArrivee;
  final double? distanceKm;
  final bool annulable;
  final VoidCallback? onAppeler;
  final VoidCallback? onMessage;
  final VoidCallback onAnnuler;

  final bool paiementEnCours;
  final bool dejaPayee;
  final ValueChanged<MoyenPaiement>? onPayer;
  final bool noteEnCours;
  final bool dejaNotee;
  final void Function(int, String?)? onNoter;
  final VoidCallback? onTerminer;

  bool get _terminee => statut == StatutCourse.terminee;

  @override
  Widget build(BuildContext context) {
    final c = chauffeur;

    return Container(
      decoration: const BoxDecoration(
        color: TaamaColors.night,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (c != null && !_terminee)
            Positioned(top: -34, left: 18, child: _Medaillon(chauffeur: c)),
          ListView(
            controller: controleur,
            padding: EdgeInsets.fromLTRB(
              18,
              (c == null || _terminee) ? 14 : 46,
              18,
              MediaQuery.paddingOf(context).bottom + 20,
            ),
            children: _terminee
                ? _contenuFin(context, c)
                : _contenuEnCours(context, c),
          ),
        ],
      ),
    );
  }

  // --- Course en cours -----------------------------------------------------

  List<Widget> _contenuEnCours(BuildContext context, ChauffeurCourse? c) {
    return [
      if (c == null)
        const _EnAttente()
      else ...[
        _LigneChauffeur(
          chauffeur: c,
          minutes: minutesAvantArrivee,
          distanceKm: distanceKm,
          statut: statut,
        ),
        const SizedBox(height: TaamaSpacing.lg),
        _Etapes(statut: statut),
        if (onAppeler != null || onMessage != null) ...[
          const SizedBox(height: TaamaSpacing.lg),
          Row(
            children: [
              if (onAppeler != null)
                Expanded(
                  child: _BoutonContact(
                    icone: Icons.call_rounded,
                    libelle: 'Appeler',
                    principal: true,
                    onTap: onAppeler!,
                  ),
                ),
              if (onAppeler != null && onMessage != null)
                const SizedBox(width: 10),
              if (onMessage != null)
                Expanded(
                  child: _BoutonContact(
                    icone: Icons.chat_bubble_outline_rounded,
                    libelle: 'Message',
                    principal: onAppeler == null,
                    onTap: onMessage!,
                  ),
                ),
            ],
          ),
        ],
      ],
      const SizedBox(height: TaamaSpacing.lg),
      _BlocTrajet(
        depart: depart,
        arrivee: arrivee,
        prixFcfa: prixFcfa,
        soldeFcfa: soldeFcfa,
      ),
      if (annulable) ...[
        const SizedBox(height: TaamaSpacing.lg),
        GlissiereAnnulation(onValide: onAnnuler),
      ],
    ];
  }

  // --- Course terminée : paiement puis notation ---------------------------

  List<Widget> _contenuFin(BuildContext context, ChauffeurCourse? c) {
    final toutFait = dejaPayee && (dejaNotee || onNoter == null);

    return [
      Center(
        child: Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: TaamaColors.nightControl,
            borderRadius: BorderRadius.circular(TaamaRadius.pill),
          ),
        ),
      ),
      const SizedBox(height: TaamaSpacing.lg),
      Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: TaamaColors.accentMint,
              borderRadius: BorderRadius.circular(TaamaRadius.md),
            ),
            child: const Icon(Icons.check_rounded,
                size: 26, color: Color(0xFF04342C)),
          ),
          const SizedBox(width: TaamaSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Vous êtes arrivé',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: TaamaColors.textOnDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Merci d’avoir voyagé avec Taama.',
                  style:
                      TextStyle(fontSize: 13, color: TaamaColors.onNightMuted),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: TaamaSpacing.lg),
      _BlocTrajet(
        depart: depart,
        arrivee: arrivee,
        prixFcfa: prixFcfa,
        soldeFcfa: soldeFcfa,
        montrerSolde: !dejaPayee,
      ),
      if (!dejaPayee && onPayer != null) ...[
        const SizedBox(height: TaamaSpacing.lg),
        _BlocPaiement(
          prixFcfa: prixFcfa,
          soldeFcfa: soldeFcfa,
          enCours: paiementEnCours,
          onPayer: onPayer!,
        ),
      ],
      if (dejaPayee) ...[
        const SizedBox(height: TaamaSpacing.md),
        const _Confirmation(texte: 'Paiement enregistré'),
      ],
      if (onNoter != null) ...[
        const SizedBox(height: TaamaSpacing.lg),
        if (dejaNotee)
          const _Confirmation(texte: 'Merci pour votre note')
        else
          BlocNotation(
            nomChauffeur: c?.nomCourt,
            urlPhoto: c?.urlPhoto,
            enCours: noteEnCours,
            // Noter avant de payer n'a pas de sens : le montant peut
            // encore bouger (attente, arrêt supplémentaire).
            actif: dejaPayee || onPayer == null,
            onNoter: onNoter!,
          ),
      ],
      if (toutFait && onTerminer != null) ...[
        const SizedBox(height: TaamaSpacing.lg),
        FilledButton(onPressed: onTerminer, child: const Text('Terminer')),
      ],
    ];
  }
}

class _Confirmation extends StatelessWidget {
  const _Confirmation({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: TaamaColors.nightRaised,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 18, color: TaamaColors.accentMint),
          const SizedBox(width: 9),
          Text(
            texte,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: TaamaColors.textOnDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paiement
// ---------------------------------------------------------------------------

class _BlocPaiement extends StatelessWidget {
  const _BlocPaiement({
    required this.prixFcfa,
    required this.soldeFcfa,
    required this.enCours,
    required this.onPayer,
  });

  final int prixFcfa;
  final int soldeFcfa;
  final bool enCours;
  final ValueChanged<MoyenPaiement> onPayer;

  @override
  Widget build(BuildContext context) {
    final suffisant = soldeFcfa >= prixFcfa;

    return Container(
      padding: const EdgeInsets.all(TaamaSpacing.lg),
      decoration: BoxDecoration(
        color: TaamaColors.nightRaised,
        borderRadius: BorderRadius.circular(TaamaRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Régler la course',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: TaamaColors.textOnDark,
            ),
          ),
          const SizedBox(height: TaamaSpacing.md),
          if (enCours)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: TaamaColors.routeNight,
                  ),
                ),
              ),
            )
          else ...[
            FilledButton.icon(
              onPressed:
                  suffisant ? () => onPayer(MoyenPaiement.portefeuille) : null,
              icon: const Icon(Icons.account_balance_wallet_rounded, size: 19),
              label: Text(
                suffisant
                    ? 'Payer ${formaterFcfa(prixFcfa)} par portefeuille'
                    : 'Solde insuffisant (${formaterFcfa(soldeFcfa)})',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => onPayer(MoyenPaiement.especes),
              style: OutlinedButton.styleFrom(
                foregroundColor: TaamaColors.textOnDark,
                side: const BorderSide(color: TaamaColors.nightBorder),
              ),
              icon: const Icon(Icons.payments_outlined, size: 19),
              label: const Text('J’ai payé en espèces'),
            ),
            if (!suffisant) ...[
              const SizedBox(height: 10),
              const Text(
                'Rechargez votre portefeuille ou réglez en espèces au chauffeur.',
                style:
                    TextStyle(fontSize: 12, color: TaamaColors.onNightMuted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notation
// ---------------------------------------------------------------------------

class BlocNotation extends StatefulWidget {
  const BlocNotation({
    super.key,
    required this.enCours,
    required this.actif,
    required this.onNoter,
    this.nomChauffeur,
    this.urlPhoto,
  });

  final bool enCours;

  /// Faux tant que la course n'est pas réglée : on n'ouvre pas la
  /// notation avant que le montant soit définitif.
  final bool actif;
  final void Function(int etoiles, String? commentaire) onNoter;
  final String? nomChauffeur;
  final String? urlPhoto;

  @override
  State<BlocNotation> createState() => _BlocNotationState();
}

class _BlocNotationState extends State<BlocNotation> {
  int _etoiles = 0;
  final TextEditingController _commentaire = TextEditingController();

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nom = widget.nomChauffeur;

    return Opacity(
      opacity: widget.actif ? 1 : 0.5,
      child: IgnorePointer(
        ignoring: !widget.actif,
        child: Container(
          padding: const EdgeInsets.all(TaamaSpacing.lg),
          decoration: BoxDecoration(
            color: TaamaColors.nightRaised,
            borderRadius: BorderRadius.circular(TaamaRadius.xl),
          ),
          child: Column(
            children: [
              if (nom != null)
                PhotoAvatar(
                  nom: nom,
                  urlPhoto: widget.urlPhoto,
                  diametre: 56,
                  couleurFond: TaamaColors.routeNight,
                  couleurTexte: TaamaColors.night,
                ),
              const SizedBox(height: TaamaSpacing.md),
              Text(
                nom == null
                    ? 'Comment s’est passée la course ?'
                    : 'Comment s’est passée la course avec $nom ?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: TaamaColors.textOnDark,
                ),
              ),
              const SizedBox(height: TaamaSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    Semantics(
                      button: true,
                      label: '$i étoile${i > 1 ? 's' : ''}',
                      selected: _etoiles == i,
                      child: IconButton(
                        onPressed: widget.enCours
                            ? null
                            : () => setState(() => _etoiles = i),
                        icon: Icon(
                          i <= _etoiles
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 34,
                          color: i <= _etoiles
                              ? TaamaColors.star
                              : TaamaColors.nightControl,
                        ),
                      ),
                    ),
                ],
              ),
              if (_etoiles > 0) ...[
                const SizedBox(height: TaamaSpacing.sm),
                TextField(
                  controller: _commentaire,
                  enabled: !widget.enCours,
                  maxLength: 300,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 14, color: TaamaColors.textOnDark),
                  decoration: InputDecoration(
                    hintText: 'Un commentaire ? (facultatif)',
                    hintStyle:
                        const TextStyle(color: TaamaColors.onNightFaint),
                    counterStyle:
                        const TextStyle(color: TaamaColors.onNightFaint),
                    filled: true,
                    fillColor: TaamaColors.night,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TaamaRadius.lg),
                      borderSide:
                          const BorderSide(color: TaamaColors.nightBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(TaamaRadius.lg),
                      borderSide: const BorderSide(
                          color: TaamaColors.routeNight, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: TaamaSpacing.sm),
                FilledButton(
                  onPressed: widget.enCours
                      ? null
                      : () {
                          final texte = _commentaire.text.trim();
                          widget.onNoter(
                              _etoiles, texte.isEmpty ? null : texte);
                        },
                  child: widget.enCours
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: TaamaColors.textOnDark,
                          ),
                        )
                      : const Text('Envoyer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Éléments partagés
// ---------------------------------------------------------------------------

class _Medaillon extends StatelessWidget {
  const _Medaillon({required this.chauffeur});

  final ChauffeurCourse chauffeur;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: TaamaColors.night,
              shape: BoxShape.circle,
            ),
            child: PhotoAvatar(
              nom: chauffeur.nomCourt,
              urlPhoto: chauffeur.urlPhoto,
              diametre: 66,
              couleurFond: TaamaColors.routeNight,
              couleurTexte: TaamaColors.night,
            ),
          ),
          if (chauffeur.note != null)
            Positioned(
              right: 6,
              bottom: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: TaamaColors.accentMint,
                  borderRadius: BorderRadius.circular(TaamaRadius.pill),
                  border: Border.all(color: TaamaColors.night, width: 2),
                ),
                child: Text(
                  formaterNote(chauffeur.note!),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF04342C),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LigneChauffeur extends StatelessWidget {
  const _LigneChauffeur({
    required this.chauffeur,
    required this.minutes,
    required this.distanceKm,
    required this.statut,
  });

  final ChauffeurCourse chauffeur;
  final int? minutes;
  final double? distanceKm;
  final StatutCourse statut;

  String get _libelleTemps =>
      statut == StatutCourse.aBord ? 'arrivée à destination' : 'arrivée';

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                chauffeur.nomCourt,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: TaamaColors.textOnDark,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: TaamaColors.surface,
                      borderRadius: BorderRadius.circular(TaamaRadius.sm),
                    ),
                    child: Text(
                      chauffeur.plaque,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: TaamaColors.textPrimary,
                      ),
                    ),
                  ),
                  if (chauffeur.vehicule != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (chauffeur.couleurVehicule != null) ...[
                          Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: chauffeur.couleurVehicule,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: TaamaColors.nightBorder, width: 1),
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          chauffeur.vehicule!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: TaamaColors.onNightMuted,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        if (minutes != null) ...[
          const SizedBox(width: TaamaSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$minutes',
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: TaamaColors.textOnDark,
                      ),
                    ),
                    const TextSpan(
                      text: ' min',
                      style: TextStyle(
                        fontSize: 16,
                        color: TaamaColors.onNightMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                distanceKm == null
                    ? _libelleTemps
                    : '$_libelleTemps · ${formaterDistance(distanceKm!)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: TaamaColors.onNightMuted,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Etapes extends StatelessWidget {
  const _Etapes({required this.statut});

  final StatutCourse statut;

  int get _indice => switch (statut) {
        StatutCourse.recherche => 0,
        StatutCourse.acceptee => 1,
        StatutCourse.enRoute => 2,
        StatutCourse.aBord => 3,
        StatutCourse.terminee => 3,
      };

  @override
  Widget build(BuildContext context) {
    const libelles = ['Accepté', 'En route vers vous', 'À bord'];

    Color barre(int i) {
      if (_indice > i + 1) return TaamaColors.accentMint;
      if (_indice == i + 1) return TaamaColors.routeNight;
      return TaamaColors.nightControl;
    }

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 3,
                  decoration: BoxDecoration(
                    color: barre(i),
                    borderRadius: BorderRadius.circular(TaamaRadius.pill),
                  ),
                ),
              ),
              if (i < 2) const SizedBox(width: 5),
            ],
          ],
        ),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 3; i++)
              Text(
                libelles[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      _indice == i + 1 ? FontWeight.w700 : FontWeight.w400,
                  color: _indice == i + 1
                      ? TaamaColors.textOnDark
                      : TaamaColors.onNightFaint,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _EnAttente extends StatelessWidget {
  const _EnAttente();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: TaamaColors.nightControl,
            borderRadius: BorderRadius.circular(TaamaRadius.pill),
          ),
        ),
        const SizedBox(height: TaamaSpacing.lg),
        const Text(
          'Recherche d’un chauffeur…',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: TaamaColors.textOnDark,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Nous prévenons les chauffeurs les plus proches de vous.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: TaamaColors.onNightMuted),
        ),
        const SizedBox(height: TaamaSpacing.lg),
        const LinearProgressIndicator(
          backgroundColor: TaamaColors.nightControl,
          color: TaamaColors.routeNight,
          minHeight: 3,
        ),
      ],
    );
  }
}

class _BoutonContact extends StatelessWidget {
  const _BoutonContact({
    required this.icone,
    required this.libelle,
    required this.principal,
    required this.onTap,
  });

  final IconData icone;
  final String libelle;
  final bool principal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fond = principal ? TaamaColors.surface : TaamaColors.nightControl;
    final couleur = principal ? TaamaColors.night : TaamaColors.textOnDark;

    return Material(
      color: fond,
      borderRadius: BorderRadius.circular(TaamaRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icone, size: 18, color: couleur),
              const SizedBox(width: 8),
              Text(
                libelle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: couleur,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlocTrajet extends StatelessWidget {
  const _BlocTrajet({
    required this.depart,
    required this.arrivee,
    required this.prixFcfa,
    required this.soldeFcfa,
    this.montrerSolde = true,
  });

  final String depart;
  final String arrivee;
  final int prixFcfa;
  final int soldeFcfa;
  final bool montrerSolde;

  @override
  Widget build(BuildContext context) {
    final soldeSuffisant = soldeFcfa >= prixFcfa;

    return Container(
      padding: const EdgeInsets.all(TaamaSpacing.lg),
      decoration: BoxDecoration(
        color: TaamaColors.nightRaised,
        borderRadius: BorderRadius.circular(TaamaRadius.xl),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  const SizedBox(height: 4),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: TaamaColors.accentMint,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                      width: 1.5, height: 22, color: TaamaColors.nightBorder),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: TaamaColors.surface,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      depart,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: TaamaColors.textOnDark,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      arrivee,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: TaamaColors.textOnDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const Divider(color: TaamaColors.nightBorder, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Prix fixe · portefeuille Taama',
                      style: TextStyle(
                        fontSize: 11,
                        color: TaamaColors.onNightFaint,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      formaterFcfa(prixFcfa),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: TaamaColors.textOnDark,
                      ),
                    ),
                  ],
                ),
              ),
              if (montrerSolde)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: soldeSuffisant
                        ? TaamaColors.nightControl
                        : TaamaColors.dangerNightBg,
                    borderRadius: BorderRadius.circular(TaamaRadius.pill),
                  ),
                  child: Text(
                    soldeSuffisant
                        ? 'Solde ${formaterFcfa(soldeFcfa)}'
                        : 'Solde insuffisant',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          soldeSuffisant ? FontWeight.w400 : FontWeight.w700,
                      color: soldeSuffisant
                          ? TaamaColors.onNightMuted
                          : TaamaColors.dangerNight,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Annuler demande un glissement complet : évite les annulations
/// accidentelles, donc les pénalités injustes et les chauffeurs mécontents.
class GlissiereAnnulation extends StatefulWidget {
  const GlissiereAnnulation({super.key, required this.onValide});

  final VoidCallback onValide;

  @override
  State<GlissiereAnnulation> createState() => _GlissiereAnnulationState();
}

class _GlissiereAnnulationState extends State<GlissiereAnnulation> {
  double _position = 0; // 0 → 1
  static const double _taillePoignee = 44;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final course = contraintes.maxWidth - _taillePoignee - 10;

        return Semantics(
          button: true,
          label: 'Annuler la course, glisser pour confirmer',
          onTap: widget.onValide,
          child: Container(
            height: 54,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: TaamaColors.nightRaised,
              borderRadius: BorderRadius.circular(TaamaRadius.pill),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: (1 - _position * 1.6).clamp(0, 1),
                  child: const Text(
                    'Glisser pour annuler',
                    style: TextStyle(
                      fontSize: 13,
                      color: TaamaColors.onNightFaint,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    offset: Offset(_position * course, 0),
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) {
                        setState(() {
                          _position =
                              (_position + d.delta.dx / course).clamp(0.0, 1.0);
                        });
                      },
                      onHorizontalDragEnd: (_) {
                        if (_position > 0.85) widget.onValide();
                        setState(() => _position = 0);
                      },
                      child: Container(
                        width: _taillePoignee,
                        height: _taillePoignee,
                        decoration: const BoxDecoration(
                          color: TaamaColors.nightControl,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: TaamaColors.dangerNight,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
