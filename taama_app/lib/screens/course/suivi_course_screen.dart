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
    this.couleurLibelle,
  });

  final String nomCourt;
  final String plaque;
  final String? urlPhoto;
  final double? note;
  final int? nombreCourses;

  /// Ex. « Toyota Corolla ». La couleur est passée à part.
  final String? vehicule;

  /// Couleur en toutes lettres, au féminin (« grise ») : voir
  /// `couleurVehiculeFeminin()` (utils/format.dart). Null → non affichée.
  final String? couleurLibelle;

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
    this.paiementActif = false,
    required this.onRetour,
    required this.onAnnuler,
    this.mapController,
    this.chauffeur,
    this.positionClient,
    this.positionDestination,
    this.positionChauffeur,
    this.glissementChauffeur,
    this.itineraire = const [],
    this.minutesAvantArrivee,
    this.distanceKm,
    this.phraseSituation,
    this.etatSuivi,
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

  /// Paiement dans l'app actif (lu sur le serveur, voir ConfigApp). Faux
  /// (mode gratuit) : ni solde, ni portefeuille, ni « Payer » ; la course se
  /// règle en espèces au chauffeur.
  final bool paiementActif;

  final LatLng? positionClient;
  final LatLng? positionDestination;
  final LatLng? positionChauffeur;

  /// Durée du glissement du véhicule vers [positionChauffeur] (voir
  /// VehiculeCarte.glissement) ; null : glissement court par défaut.
  final Duration? glissementChauffeur;
  final List<LatLng> itineraire;

  final int? minutesAvantArrivee;
  final double? distanceKm;

  /// Phrase calculée serveur (« … vient de tourner sur votre rue »).
  /// Null → ligne non affichée : jamais de texte inventé côté app.
  final String? phraseSituation;

  /// État du suivi temps réel (« Reconnexion au suivi… »). Prioritaire sur
  /// [phraseSituation] : un marqueur figé ne reste jamais sans explication.
  final String? etatSuivi;

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
      // Carte claire : icônes de la barre d'état foncées, sinon invisibles.
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: TaamaColors.mapPlaceholder,
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
                      glissement: glissementChauffeur,
                    ),
                ],
                itineraire: itineraire,
                themeNuit: false,
                margeCadrage: const EdgeInsets.fromLTRB(56, 110, 56, 320),
                // Le panneau du bas couvre le coin inférieur : l'attribution
                // passe sous la barre haute (boutons de 44 px à haut + 12).
                alignementAttribution: Alignment.topLeft,
                margeAttribution: EdgeInsets.only(
                  left: 14,
                  top: MediaQuery.paddingOf(context).top + 64,
                ),
              ),
            ),
            _BarreHaute(
              onRetour: onRetour,
              onPartager: _terminee ? null : onPartager,
              onSos: _terminee ? null : onSos,
            ),
            if ((etatSuivi ?? phraseSituation) != null && !_terminee)
              Positioned(
                left: 14,
                bottom: hauteur * 0.46,
                child: _PhraseSituation(
                  texte: (etatSuivi ?? phraseSituation)!,
                  alerte: etatSuivi != null,
                ),
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
                paiementActif: paiementActif,
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
  const _PhraseSituation({required this.texte, this.alerte = false});

  final String texte;

  /// Suivi dégradé (reconnexion, position périmée) : point ambre au lieu
  /// du vert « en direct ».
  final bool alerte;

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
            decoration: BoxDecoration(
              // Ambre du thème, lisible sur la feuille nuit (warning est un
              // brun prévu pour du texte sur fond clair).
              color: alerte ? TaamaColors.star : TaamaColors.accentMint,
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
    required this.paiementActif,
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
  final bool paiementActif;
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
      child: ListView(
        controller: controleur,
        padding: EdgeInsets.fromLTRB(
          18,
          14,
          18,
          MediaQuery.paddingOf(context).bottom + 20,
        ),
        children: _terminee
            ? _contenuFin(context, c)
            : _contenuEnCours(context, c),
      ),
    );
  }

  // --- Course en cours -----------------------------------------------------

  List<Widget> _contenuEnCours(BuildContext context, ChauffeurCourse? c) {
    return [
      if (c == null)
        const _EnAttente()
      else ...[
        // Temps d'arrivée en tête, masqué tant qu'il est inconnu : jamais
        // « 0 » ni « — » (voir SuiviCoursePage._mettreAJourItineraire).
        _TempsArrivee(
          minutes: minutesAvantArrivee,
          distanceKm: distanceKm,
          statut: statut,
        ),
        _CarteChauffeur(chauffeur: c),
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
        paiementActif: paiementActif,
        montrerSolde: paiementActif,
      ),
      if (annulable) ...[
        const SizedBox(height: TaamaSpacing.lg),
        GlissiereAnnulation(onValide: onAnnuler),
      ],
    ];
  }

  // --- Course terminée : paiement puis notation ---------------------------

  List<Widget> _contenuFin(BuildContext context, ChauffeurCourse? c) {
    // Mode gratuit : réglée en espèces hors de l'app, rien n'attend `paye`
    // (sinon ni note ni « Terminer » ne seraient jamais possibles).
    final regle = dejaPayee || !paiementActif;
    final toutFait = regle && (dejaNotee || onNoter == null);

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
                size: 26, color: TaamaColors.onAccentMint),
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
        paiementActif: paiementActif,
        montrerSolde: paiementActif && !dejaPayee,
      ),
      if (paiementActif && !dejaPayee && onPayer != null) ...[
        const SizedBox(height: TaamaSpacing.lg),
        _BlocPaiement(
          prixFcfa: prixFcfa,
          soldeFcfa: soldeFcfa,
          enCours: paiementEnCours,
          onPayer: onPayer!,
        ),
      ],
      if (paiementActif && dejaPayee) ...[
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
            actif: regle || onPayer == null,
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
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
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

/// Temps d'arrivée en tête de la feuille, en grand. Masqué tant qu'il est
/// inconnu (jamais « 0 » ni « — ») ; le chiffre change en fondu.
class _TempsArrivee extends StatelessWidget {
  const _TempsArrivee({
    required this.minutes,
    required this.distanceKm,
    required this.statut,
  });

  final int? minutes;
  final double? distanceKm;
  final StatutCourse statut;

  String get _libelle =>
      statut == StatutCourse.aBord ? 'arrivée à destination' : 'arrivée';

  @override
  Widget build(BuildContext context) {
    final m = minutes;
    if (m == null) return const SizedBox.shrink();
    final reduit = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: TaamaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: reduit ? Duration.zero : const Duration(milliseconds: 300),
            transitionBuilder: (enfant, animation) =>
                FadeTransition(opacity: animation, child: enfant),
            child: Text.rich(
              key: ValueKey(m),
              TextSpan(
                children: [
                  TextSpan(
                    text: '$m',
                    style: const TextStyle(
                      fontSize: 32,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: TaamaColors.textOnDark,
                    ),
                  ),
                  const TextSpan(
                    text: ' min',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: TaamaColors.onNightMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            distanceKm == null ? _libelle : '$_libelle · ${formaterDistance(distanceKm!)}',
            style: const TextStyle(fontSize: 13, color: TaamaColors.onNightMuted),
          ),
        ],
      ),
    );
  }
}

/// Chauffeur : photo ronde à côté du nom (repli sur les initiales), note et
/// nombre de courses, véhicule en toutes lettres avec sa couleur, plaque
/// en évidence — tout ce qu'il faut pour reconnaître la voiture.
class _CarteChauffeur extends StatelessWidget {
  const _CarteChauffeur({required this.chauffeur});

  final ChauffeurCourse chauffeur;

  /// « 4,9 · 120 courses », sans segment vide.
  String? get _ligneConfiance {
    final n = chauffeur.nombreCourses;
    final morceaux = [
      if (chauffeur.note != null) formaterNote(chauffeur.note!),
      if (n != null && n > 0) n == 1 ? '1 course' : '$n courses',
    ];
    return morceaux.isEmpty ? null : morceaux.join(' · ');
  }

  /// « Toyota Corolla grise », sans « null » ni couleur devinée.
  String? get _vehicule {
    final morceaux = [
      if (chauffeur.vehicule != null) chauffeur.vehicule!,
      if (chauffeur.couleurLibelle != null) chauffeur.couleurLibelle!,
    ];
    return morceaux.isEmpty ? null : morceaux.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final confiance = _ligneConfiance;
    final vehicule = _vehicule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            PhotoAvatar(
              nom: chauffeur.nomCourt,
              urlPhoto: chauffeur.urlPhoto,
              diametre: 60,
              couleurFond: TaamaColors.routeNight,
              couleurTexte: TaamaColors.night,
            ),
            const SizedBox(width: TaamaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  if (confiance != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (chauffeur.note != null) ...[
                          const Icon(Icons.star_rounded, size: 15, color: TaamaColors.star),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            confiance,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: TaamaColors.onNightMuted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: TaamaSpacing.md),
        Row(
          children: [
            if (chauffeur.couleurVehicule != null) ...[
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: chauffeur.couleurVehicule,
                  shape: BoxShape.circle,
                  border: Border.all(color: TaamaColors.nightBorder, width: 1.5),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: vehicule == null
                  ? const SizedBox.shrink()
                  : Text(
                      vehicule,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: TaamaColors.textOnDark,
                      ),
                    ),
            ),
            if (chauffeur.plaque.trim().isNotEmpty) ...[
              const SizedBox(width: TaamaSpacing.md),
              _Plaque(texte: chauffeur.plaque.trim()),
            ],
          ],
        ),
      ],
    );
  }
}

/// Plaque d'immatriculation : encadré clair, bordure, gras et espacé,
/// lisible de loin.
class _Plaque extends StatelessWidget {
  const _Plaque({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Plaque $texte',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: TaamaColors.surface,
          borderRadius: BorderRadius.circular(TaamaRadius.sm),
          border: Border.all(color: TaamaColors.textPrimary, width: 1.5),
        ),
        child: Text(
          texte.toUpperCase(),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
            height: 1.1,
            color: TaamaColors.textPrimary,
          ),
        ),
      ),
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
    final duree = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 600);

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              Expanded(
                child: _SegmentEtape(
                  // Étape atteinte : le segment se remplit de gauche à
                  // droite ; vert une fois dépassée, accent tant qu'en cours.
                  rempli: _indice >= i + 1,
                  couleur: _indice > i + 1 ? TaamaColors.accentMint : TaamaColors.routeNight,
                  duree: duree,
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

/// Un segment de la barre d'étapes : piste sombre, remplissage animé.
class _SegmentEtape extends StatelessWidget {
  const _SegmentEtape({required this.rempli, required this.couleur, required this.duree});

  final bool rempli;
  final Color couleur;
  final Duration duree;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(TaamaRadius.pill),
      child: Container(
        height: 4,
        color: TaamaColors.nightControl,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          // Part de 0 à l'affichage : l'étape en cours se remplit sous les yeux.
          tween: Tween(begin: 0, end: rempli ? 1 : 0),
          duration: duree,
          curve: Curves.easeOutCubic,
          builder: (_, facteur, __) => FractionallySizedBox(
            widthFactor: facteur,
            child: AnimatedContainer(duration: duree, color: couleur),
          ),
        ),
      ),
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
          'Vous pouvez quitter l’application : vous serez prévenu dès qu’un chauffeur accepte.',
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
    required this.paiementActif,
    this.montrerSolde = true,
  });

  final String depart;
  final String arrivee;
  final int prixFcfa;
  final int soldeFcfa;
  final bool paiementActif;
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
                    Text(
                      paiementActif
                          ? 'Prix annoncé · portefeuille Taama'
                          : 'Prix annoncé · paiement en espèces au chauffeur',
                      style: const TextStyle(
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
