import 'package:flutter/material.dart';

import '../models/verification_identite.dart';
import '../services/api_service.dart';
import '../services/config_app.dart';
import '../services/courses_en_cours.dart';
import '../services/deconnexion.dart';
import '../services/fin_de_session.dart';
import '../services/mise_a_jour.dart';
import '../services/politique_confidentialite.dart';
import '../theme/taama_theme.dart';
import '../widgets/dialogue_deconnexion.dart';
import '../widgets/dialogue_suppression_compte.dart';
import '../widgets/photo_avatar.dart';
import 'avis_app_screen.dart';
import 'connexion_screen.dart';
import 'mes_conversations_client_screen.dart';
import 'mes_reservations_screen.dart';
import 'portefeuille_screen.dart';
import 'profil_screen.dart';
import 'verification_identite_page.dart';

/// Écran Compte (v4). Logique inchangée (profil, déconnexion, suppression de
/// compte, portefeuille en mode payant) ; habillage TaamaColors/TaamaText,
/// avatar PhotoAvatar (initiales) au lieu du cercle « ? ».
class EcranCompte extends StatefulWidget {
  const EcranCompte({super.key});

  @override
  State<EcranCompte> createState() => _EcranCompteState();
}

class _EcranCompteState extends State<EcranCompte> {
  Map<String, dynamic>? _profil;
  bool _suppressionEnCours = false;
  bool _deconnexionEnCours = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final profil = await ApiService.monProfil();
      if (mounted) setState(() => _profil = profil);
    } catch (_) {}
  }

  /// Déconnexion (Deconnexion), après confirmation : refusée pendant une
  /// course ou une livraison, connue de l'app (CoursesEnCours, relue sur le
  /// serveur) ou du serveur (409). Sinon l'écran de connexion s'ouvre, même
  /// si le serveur n'a pas répondu (il le dit alors).
  Future<void> _deconnecter() => FinDeSession.pendant(_menerDeconnexion);

  // Sous FinDeSession.pendant : un 401 du polling de l'accueil ne vole pas
  // l'issue ni le message de cet écran.
  Future<void> _menerDeconnexion() async {
    if (_deconnexionEnCours) return;
    if (!await demanderConfirmationDeconnexion(context)) return;
    if (!mounted) return;
    setState(() => _deconnexionEnCours = true);
    IssueDeconnexion? issue;
    try {
      issue = await Deconnexion.seDeconnecter(
          courseEnCoursLocale: await CoursesEnCours.enCoursApresRelecture());
      if (issue.estDeconnecte) await CoursesEnCours.toutEffacer();
    } catch (e) {
      debugPrint('Erreur déconnexion : $e');
    } finally {
      if (mounted) setState(() => _deconnexionEnCours = false);
    }
    if (!mounted) return;
    if (!(issue?.estDeconnecte ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(issue == IssueDeconnexion.courseEnCours
            ? Deconnexion.messageCourseEnCours
            : 'Déconnexion impossible pour le moment. Réessaie.'),
      ));
      return;
    }
    final messager = ScaffoldMessenger.of(context);
    _ouvrirConnexion();
    if (issue == IssueDeconnexion.deconnecteHorsReseau) {
      messager.showSnackBar(const SnackBar(content: Text(messageDeconnexionHorsReseau)));
    }
  }

  void _ouvrirConnexion() {
    // Version trop ancienne (426) : l'écran « Mise à jour requise » reste seul.
    if (MiseAJour.ecranAffiche) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const EcranConnexion()),
      (route) => false,
    );
  }

  Future<void> _supprimerCompte() => FinDeSession.pendant(_menerSuppressionCompte);

  // Sous FinDeSession.pendant : un 401 du polling de l'accueil (le compte
  // vient d'être supprimé) ne remplace pas le message de la suppression.
  Future<void> _menerSuppressionCompte() async {
    if (!await demanderConfirmationSuppression(context)) return;
    if (!mounted) return;
    setState(() => _suppressionEnCours = true);
    String messageFinal;
    try {
      await ApiService.supprimerMonCompte();
      messageFinal = 'Ton compte a été supprimé.';
    } on SuppressionCompteRefuseeException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        duration: const Duration(seconds: 8),
      ));
      return;
    } on SessionInvalideException {
      messageFinal = "Ta session n'est plus valide. Si tu venais de demander "
          'la suppression, elle a bien été prise en compte.';
    } catch (_) {
      // Réponse perdue ou trop lente, mais un 401 de la session est arrivé
      // entre-temps (FinDeSession) : le serveur a bien supprimé le compte.
      if (!FinDeSession.fermeeDuranteOperation) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Impossible de joindre Taama. Vérifie ta connexion et réessaie.'),
        ));
        return;
      }
      messageFinal = "Ta session n'est plus valide. Si tu venais de demander "
          'la suppression, elle a bien été prise en compte.';
    } finally {
      if (mounted) setState(() => _suppressionEnCours = false);
    }
    if (!mounted) return;
    final messager = ScaffoldMessenger.of(context);
    // Compte supprimé : la session de l'appareil est effacée, sans requête.
    await Deconnexion.effacerSessionLocale();
    await CoursesEnCours.toutEffacer();
    if (mounted) _ouvrirConnexion();
    messager.showSnackBar(SnackBar(content: Text(messageFinal)));
  }

  /// Statut de la vérification (facultative), null tant qu'il est inconnu.
  String? get _libelleIdentite =>
      switch (statutIdentiteDepuis(_profil?['verification_identite'])) {
        StatutIdentite.nonSoumis => 'Facultatif',
        StatutIdentite.enAttente => 'En cours de vérification',
        StatutIdentite.approuve => 'Vérifiée',
        StatutIdentite.refuse => 'Refusée : envoie une autre photo',
        null => null,
      };

  String get _nomComplet {
    final prenom = _profil?['first_name']?.toString() ?? '';
    final nom = _profil?['last_name']?.toString() ?? '';
    return '$prenom $nom'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final tel = _profil?['telephone']?.toString() ?? '';

    return Scaffold(
      backgroundColor: TaamaColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _enTete(tel),
              const SizedBox(height: 20),
              ValueListenableBuilder<bool>(
                valueListenable: ConfigApp.paiementActif,
                builder: (context, paiementActif, _) => _section('Mon compte', [
                  // Mode gratuit (lu sur le serveur) : pas de portefeuille.
                  if (paiementActif)
                    _item(Icons.account_balance_wallet_rounded, 'Mon portefeuille',
                        () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const EcranPortefeuille(estChauffeur: false)),
                            )),
                  _item(Icons.event_seat_rounded, 'Mes réservations',
                      () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const EcranMesReservations()),
                          )),
                  _item(Icons.chat_bubble_rounded, 'Mes messages',
                      () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const MesConversationsClientScreen()),
                          )),
                  _item(Icons.verified_user_outlined, 'Vérifier mon identité',
                      () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PageVerificationIdentite()),
                        );
                        _charger();
                      },
                      sousTitre: _libelleIdentite),
                ]),
              ),
              const SizedBox(height: 16),
              _section('Taama', [
                _item(Icons.star_rounded, 'Donner mon avis',
                    () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const EcranAvisApp()),
                        ),
                    couleur: TaamaColors.star),
                _item(Icons.privacy_tip_outlined, 'Politique de confidentialité',
                    () => ouvrirPolitiqueConfidentialite(context)),
              ]),
              const SizedBox(height: 16),
              _carteDeconnexion(),
              const SizedBox(height: 24),
              // Volontairement discret et séparé de « Se déconnecter » : action
              // irréversible, protégée par une saisie de confirmation.
              TextButton.icon(
                onPressed: _suppressionEnCours ? null : _supprimerCompte,
                style: TextButton.styleFrom(foregroundColor: TaamaColors.danger),
                icon: _suppressionEnCours
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: TaamaColors.danger),
                      )
                    : const Icon(Icons.delete_forever_outlined),
                label: const Text('Supprimer mon compte'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _enTete(String tel) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TaamaColors.navy,
        borderRadius: BorderRadius.circular(TaamaRadius.xl),
      ),
      child: Row(
        children: [
          PhotoAvatar(
            nom: _nomComplet,
            diametre: 60,
            couleurFond: TaamaColors.primary,
            couleurTexte: Colors.white,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nomComplet.isEmpty ? 'Mon compte' : _nomComplet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TaamaText.title.copyWith(color: Colors.white, fontSize: 18),
                ),
                if (tel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(tel,
                      style: TaamaText.body.copyWith(
                          color: TaamaColors.onNavyMuted, fontSize: 13)),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Modifier mon profil',
            icon: const Icon(Icons.edit_rounded, color: Colors.white),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EcranProfil()),
              );
              _charger();
            },
          ),
        ],
      ),
    );
  }

  Widget _carteDeconnexion() {
    return Container(
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        boxShadow: TaamaShadows.card,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TaamaRadius.lg)),
        leading: CircleAvatar(
          backgroundColor: TaamaColors.danger.withValues(alpha: 0.12),
          child: const Icon(Icons.logout_rounded, color: TaamaColors.danger),
        ),
        title: Text('Se déconnecter',
            style: TaamaText.body.copyWith(
                color: TaamaColors.danger, fontWeight: FontWeight.w800)),
        trailing: _deconnexionEnCours
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: TaamaColors.danger),
              )
            : null,
        onTap: _deconnexionEnCours ? null : _deconnecter,
      ),
    );
  }

  Widget _section(String titre, List<Widget> items) {
    return Container(
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        boxShadow: TaamaShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(titre.toUpperCase(),
                style: TaamaText.muted.copyWith(
                    fontSize: 11, letterSpacing: 0.6)),
          ),
          ...items,
        ],
      ),
    );
  }

  Widget _item(IconData icone, String label, VoidCallback onTap,
      {Color? couleur, String? sousTitre}) {
    final c = couleur ?? TaamaColors.primary;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: c.withValues(alpha: 0.12),
        child: Icon(icone, color: c, size: 20),
      ),
      title: Text(label, style: TaamaText.body.copyWith(fontWeight: FontWeight.w700)),
      subtitle: sousTitre == null
          ? null
          : Text(sousTitre, style: TaamaText.muted.copyWith(fontSize: 12.5)),
      trailing: const Icon(Icons.chevron_right_rounded, color: TaamaColors.textSecondary),
      onTap: onTap,
    );
  }
}
