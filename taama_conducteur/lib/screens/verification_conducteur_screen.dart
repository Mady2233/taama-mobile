// DESIGN_V4
//
// Vérification du conducteur (KYC).
//
// Inchangé : chargement du profil (monProfilConducteur + statutVerification
// si refusé), documents requis selon le type de transport (Moto : pièce +
// numéro de caisse ; Voiture : pièce + permis + assurance ; photo si le
// profil n'en a pas), envoi via soumettreVerification, messages d'erreur.
//
// Nouveau :
// - frise des étapes (Documents → Vérification → Validé) ;
// - compteur « x / n documents » avec barre de progression animée ;
// - cartes document avec coche, aperçu et « Remplacer » ;
// - attente : sablier animé + tirer pour rafraîchir le statut ;
// - validé : coche qui apparaît en rebond ;
// - photos redimensionnées (1600 px max) avant envoi : moins de data ;
// - corrections : setState après sélection protégé par `mounted`, refus
//   d'accès caméra/galerie géré (plus de crash), numéro de caisse limité à
//   30 caractères, plus d'emoji dans les textes.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../theme/couleurs_taama.dart';

/// Écran de vérification du conducteur (KYC) : soumission des documents
/// requis selon le type de transport, et suivi du statut de validation par
/// l'admin.
class EcranVerificationConducteur extends StatefulWidget {
  const EcranVerificationConducteur({super.key});

  @override
  State<EcranVerificationConducteur> createState() => _EcranVerificationConducteurState();
}

class _EcranVerificationConducteurState extends State<EcranVerificationConducteur> {
  bool _chargement = true;
  bool _envoi = false;
  String? _erreurChargement;

  String _typeTransport = 'Voiture';
  String _statut = 'non_soumis';
  bool _aPhotoProfil = false;
  String _motifRefus = '';

  File? _piece;
  File? _permis;
  File? _assurance;
  File? _photo;
  final TextEditingController _controleurNumeroCaisse = TextEditingController();

  final ImagePicker _picker = ImagePicker();

  bool get _estMoto => _typeTransport == 'Moto';

  @override
  void initState() {
    super.initState();
    _controleurNumeroCaisse.addListener(_rafraichirCompteur);
    _chargerProfil();
  }

  @override
  void dispose() {
    _controleurNumeroCaisse.removeListener(_rafraichirCompteur);
    _controleurNumeroCaisse.dispose();
    super.dispose();
  }

  void _rafraichirCompteur() {
    if (mounted) setState(() {});
  }

  /// [silencieux] : rafraîchissement sans masquer l'écran (tirer pour
  /// rafraîchir sur l'état « en attente »).
  Future<void> _chargerProfil({bool silencieux = false}) async {
    setState(() {
      if (!silencieux) _chargement = true;
      _erreurChargement = null;
    });
    try {
      final profil = await ApiService.monProfilConducteur();
      final statut = profil['statut_verification']?.toString() ?? 'non_soumis';
      var motif = '';
      if (statut == 'refuse') {
        try {
          final donneesStatut = await ApiService.statutVerification();
          motif = donneesStatut['motif_refus']?.toString() ?? '';
        } catch (_) {
          // Complément d'affichage seulement : son absence ne bloque pas l'écran.
        }
      }
      if (!mounted) return;
      setState(() {
        _typeTransport = profil['type_transport']?.toString() ?? 'Voiture';
        _statut = statut;
        _aPhotoProfil = profil['a_photo_profil'] as bool? ?? false;
        _motifRefus = motif;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreurChargement = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _choisirPhoto(void Function(File) onChoisie) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const _PastilleIcone(icone: Icons.camera_alt_rounded),
                title: const Text('Prendre une photo',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Pose le document à plat, bien éclairé'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const _PastilleIcone(icone: Icons.photo_library_rounded),
                title: const Text('Choisir depuis la galerie',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;

    XFile? image;
    try {
      image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        // Une photo de 4000 px pèse plusieurs Mo : 1600 px suffit largement
        // pour lire un document, et économise la data du chauffeur.
        maxWidth: 1600,
        maxHeight: 1600,
      );
    } catch (e) {
      // Accès caméra / galerie refusé, ou appareil sans caméra.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Impossible d'ouvrir la caméra ou la galerie. "
            "Vérifie les autorisations de l'application."),
      ));
      return;
    }
    if (image == null || !mounted) return;
    HapticFeedback.selectionClick();
    final fichier = File(image.path);
    setState(() => onChoisie(fichier));
  }

  Future<void> _soumettre() async {
    if (_piece == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute une photo de ta pièce d\'identité.')),
      );
      return;
    }
    if (_estMoto) {
      if (_controleurNumeroCaisse.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Renseigne ton numéro de caisse.')),
        );
        return;
      }
    } else {
      if (_permis == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoute une photo de ton permis de conduire.')),
        );
        return;
      }
      if (_assurance == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoute une photo de ton attestation d\'assurance.')),
        );
        return;
      }
    }
    if (!_aPhotoProfil && _photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajoute une photo de toi.')),
      );
      return;
    }

    setState(() => _envoi = true);
    try {
      await ApiService.soumettreVerification(
        piece: _piece!,
        permis: _permis,
        assurance: _assurance,
        photo: _photo,
        numeroCaisse: _estMoto ? _controleurNumeroCaisse.text.trim() : null,
      );

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documents reçus, vérification en cours (24-48h).')),
      );
      await _chargerProfil();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString().replaceAll("Exception: ", "")}')),
      );
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  // ─── Progression ───

  int get _nbRequis => (_estMoto ? 2 : 3) + (_aPhotoProfil ? 0 : 1);

  int get _nbFournis {
    var n = _piece != null ? 1 : 0;
    if (_estMoto) {
      if (_controleurNumeroCaisse.text.trim().isNotEmpty) n++;
    } else {
      if (_permis != null) n++;
      if (_assurance != null) n++;
    }
    if (!_aPhotoProfil && _photo != null) n++;
    return n;
  }

  /// Étape de la frise : 0 documents, 1 vérification, 2 validé.
  int get _etape => switch (_statut) {
        'en_attente' => 1,
        'approuve' => 2,
        _ => 0,
      };

  // ─── Construction ───

  @override
  Widget build(BuildContext context) {
    final nuit = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vérification du profil'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: CouleursTaama.terreCuite))
          : _corps(nuit),
    );
  }

  Widget _corps(bool nuit) {
    if (_erreurChargement != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded,
                  size: 44, color: CouleursTaama.indigo.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(_erreurChargement!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _chargerProfil, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    final Widget contenu = switch (_statut) {
      'en_attente' => _contenuEnAttente(nuit),
      'approuve' => _contenuApprouve(nuit),
      _ => _formulaire(nuit),
    };

    return RefreshIndicator(
      color: CouleursTaama.terreCuite,
      onRefresh: () => _chargerProfil(silencieux: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FriseEtapes(etape: _etape, refuse: _statut == 'refuse', nuit: nuit),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 350),
              child: KeyedSubtree(key: ValueKey(_statut), child: contenu),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenuEnAttente(bool nuit) {
    final documents = _estMoto
        ? "pièce d'identité, numéro de caisse"
        : "pièce d'identité, permis, assurance";
    return _CarteEtat(
      nuit: nuit,
      couleur: CouleursTaama.or,
      visuel: const _SablierAnime(),
      titre: 'Vérification en cours',
      texte: "L'équipe Taama vérifie tes documents sous 24 à 48 h. "
          'Tu peux continuer à utiliser l’application en attendant.',
      pied: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Documents soumis : $documents.',
              style: TextStyle(color: _secondaire(nuit), fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.swipe_down_rounded, size: 16, color: _secondaire(nuit)),
              const SizedBox(width: 6),
              Text('Tire vers le bas pour actualiser',
                  style: TextStyle(color: _secondaire(nuit), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contenuApprouve(bool nuit) {
    return _CarteEtat(
      nuit: nuit,
      couleur: Colors.green.shade600,
      visuel: const _CocheApparition(),
      titre: 'Compte vérifié',
      texte: 'Tes documents sont validés. Les clients voient le badge '
          '« Vérifié » sur ton profil.',
    );
  }

  Widget _formulaire(bool nuit) {
    final fournis = _nbFournis;
    final requis = _nbRequis;
    final complet = fournis >= requis;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_statut == 'refuse') ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Documents refusés',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        _motifRefus.isNotEmpty
                            ? 'Motif : $_motifRefus'
                            : 'Renvoie des photos nettes et lisibles.',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Compteur + barre
        Row(
          children: [
            Expanded(
              child: Text(
                _estMoto ? 'Documents moto' : 'Documents voiture',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _principal(nuit),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                '$fournis / $requis',
                key: ValueKey(fournis),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: complet ? Colors.green.shade600 : CouleursTaama.terreCuite,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: requis == 0 ? 0 : fournis / requis),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: CouleursTaama.indigo.withValues(alpha: 0.1),
              color: complet ? Colors.green.shade600 : CouleursTaama.terreCuite,
            ),
          ),
        ),
        const SizedBox(height: 20),

        _CarteDocument(
          nuit: nuit,
          icone: Icons.badge_rounded,
          titre: "Pièce d'identité",
          aide: "Carte NINA, passeport ou carte d'identité, recto",
          photo: _piece,
          onTap: () => _choisirPhoto((f) => _piece = f),
        ),
        if (_estMoto)
          _CarteNumeroCaisse(nuit: nuit, controleur: _controleurNumeroCaisse)
        else ...[
          _CarteDocument(
            nuit: nuit,
            icone: Icons.credit_card_rounded,
            titre: 'Permis de conduire',
            aide: 'Recto, toutes les informations lisibles',
            photo: _permis,
            onTap: () => _choisirPhoto((f) => _permis = f),
          ),
          _CarteDocument(
            nuit: nuit,
            icone: Icons.verified_user_rounded,
            titre: "Attestation d'assurance",
            aide: 'En cours de validité',
            photo: _assurance,
            onTap: () => _choisirPhoto((f) => _assurance = f),
          ),
        ],
        if (!_aPhotoProfil)
          _CarteDocument(
            nuit: nuit,
            icone: Icons.face_rounded,
            titre: 'Photo de toi',
            aide: 'Visage dégagé, sans lunettes de soleil',
            photo: _photo,
            onTap: () => _choisirPhoto((f) => _photo = f),
          ),

        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.lock_rounded, size: 14, color: _secondaire(nuit)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                "Tes documents servent uniquement à vérifier ton identité.",
                style: TextStyle(fontSize: 12, color: _secondaire(nuit)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: complet && !_envoi
                ? [
                    BoxShadow(
                      color: CouleursTaama.terreCuite.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: ElevatedButton(
            onPressed: _envoi ? null : _soumettre,
            style: ElevatedButton.styleFrom(
              backgroundColor: CouleursTaama.terreCuite,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _envoi
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _statut == 'refuse' ? 'Renvoyer les documents' : 'Envoyer pour vérification',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
          ),
        ),
      ],
    );
  }
}

Color _principal(bool nuit) => nuit ? CouleursTaama.blanc : CouleursTaama.indigo;
Color _secondaire(bool nuit) => nuit ? CouleursTaama.nuitTexteSecondaire : Colors.grey.shade600;
Color _fondCarte(bool nuit) => nuit ? CouleursTaama.nuitPanneau : Colors.white;

// ─── Widgets ───

class _PastilleIcone extends StatelessWidget {
  const _PastilleIcone({required this.icone});
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: CouleursTaama.indigo.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icone, color: CouleursTaama.indigo, size: 22),
    );
  }
}

/// Frise Documents → Vérification → Validé.
class _FriseEtapes extends StatelessWidget {
  const _FriseEtapes({required this.etape, required this.refuse, required this.nuit});

  final int etape;
  final bool refuse;
  final bool nuit;

  static const _libelles = ['Documents', 'Vérification', 'Validé'];
  static const _icones = [
    Icons.upload_file_rounded,
    Icons.hourglass_top_rounded,
    Icons.verified_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final duree = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 400);
    final children = <Widget>[];
    for (var i = 0; i < 3; i++) {
      final fait = i < etape || etape == 2;
      final actif = i == etape;
      final couleur = (i == 0 && refuse)
          ? Colors.red
          : (fait ? Colors.green.shade600 : (actif ? CouleursTaama.terreCuite : Colors.grey));
      children.add(Expanded(
        child: Column(
          children: [
            AnimatedContainer(
              duration: duree,
              width: actif ? 44 : 36,
              height: actif ? 44 : 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (fait || actif) ? couleur : couleur.withValues(alpha: 0.15),
                boxShadow: actif
                    ? [BoxShadow(color: couleur.withValues(alpha: 0.35), blurRadius: 12)]
                    : const [],
              ),
              child: Icon(
                fait && !(i == 0 && refuse) ? Icons.check_rounded : _icones[i],
                color: (fait || actif) ? Colors.white : couleur,
                size: actif ? 22 : 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _libelles[i],
              style: TextStyle(
                fontSize: 12,
                fontWeight: actif ? FontWeight.w800 : FontWeight.w600,
                color: actif ? _principal(nuit) : _secondaire(nuit),
              ),
            ),
          ],
        ),
      ));
      if (i < 2) {
        children.add(Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: i < etape ? 1 : 0),
                duration: duree,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 3,
                  backgroundColor: Colors.grey.withValues(alpha: 0.25),
                  color: Colors.green.shade600,
                ),
              ),
            ),
          ),
        ));
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: children);
  }
}

/// Carte d'un document à photographier.
class _CarteDocument extends StatelessWidget {
  const _CarteDocument({
    required this.nuit,
    required this.icone,
    required this.titre,
    required this.aide,
    required this.photo,
    required this.onTap,
  });

  final bool nuit;
  final IconData icone;
  final String titre;
  final String aide;
  final File? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fourni = photo != null;
    final duree = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _fondCarte(nuit),
        borderRadius: BorderRadius.circular(18),
        elevation: 1,
        shadowColor: Colors.black12,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: duree,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: fourni
                    ? Colors.green.shade600.withValues(alpha: 0.6)
                    : CouleursTaama.indigo.withValues(alpha: 0.12),
                width: fourni ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Aperçu ou icône
                AnimatedSwitcher(
                  duration: duree,
                  transitionBuilder: (enfant, a) => ScaleTransition(scale: a, child: enfant),
                  child: ClipRRect(
                    key: ValueKey(photo?.path ?? 'vide'),
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: fourni
                          ? Image.file(
                              photo!,
                              fit: BoxFit.cover,
                              // Décode une vignette, pas la photo entière.
                              cacheWidth: 216,
                            )
                          : Container(
                              color: CouleursTaama.indigo.withValues(alpha: 0.08),
                              child: Icon(icone, color: CouleursTaama.indigo, size: 30),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titre,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _principal(nuit),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fourni ? 'Photo ajoutée · touche pour remplacer' : aide,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: fourni ? Colors.green.shade700 : _secondaire(nuit),
                          fontWeight: fourni ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: duree,
                  transitionBuilder: (enfant, a) => ScaleTransition(
                    scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                    child: enfant,
                  ),
                  child: fourni
                      ? Container(
                          key: const ValueKey('ok'),
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.green.shade600,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                        )
                      : Icon(
                          Icons.add_a_photo_rounded,
                          key: const ValueKey('ajout'),
                          color: CouleursTaama.terreCuite,
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

class _CarteNumeroCaisse extends StatelessWidget {
  const _CarteNumeroCaisse({required this.nuit, required this.controleur});

  final bool nuit;
  final TextEditingController controleur;

  @override
  Widget build(BuildContext context) {
    final rempli = controleur.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        decoration: BoxDecoration(
          color: _fondCarte(nuit),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: rempli
                ? Colors.green.shade600.withValues(alpha: 0.6)
                : CouleursTaama.indigo.withValues(alpha: 0.12),
            width: rempli ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.two_wheeler_rounded, color: CouleursTaama.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Numéro de caisse',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _principal(nuit),
                    ),
                  ),
                ),
                if (rempli)
                  Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 22),
              ],
            ),
            TextField(
              controller: controleur,
              maxLength: 30,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Ex. 1234',
                border: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte de statut (en attente / validé).
class _CarteEtat extends StatelessWidget {
  const _CarteEtat({
    required this.nuit,
    required this.couleur,
    required this.visuel,
    required this.titre,
    required this.texte,
    this.pied,
  });

  final bool nuit;
  final Color couleur;
  final Widget visuel;
  final String titre;
  final String texte;
  final Widget? pied;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _fondCarte(nuit),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: couleur.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: couleur.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: visuel),
          const SizedBox(height: 16),
          Center(
            child: Text(
              titre,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: couleur),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            texte,
            textAlign: TextAlign.center,
            style: TextStyle(color: _principal(nuit), height: 1.4),
          ),
          if (pied != null) ...[
            const SizedBox(height: 16),
            Divider(color: couleur.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            pied!,
          ],
        ],
      ),
    );
  }
}

/// Sablier qui se retourne doucement, avec un halo.
class _SablierAnime extends StatefulWidget {
  const _SablierAnime();

  @override
  State<_SablierAnime> createState() => _SablierAnimeState();
}

class _SablierAnimeState extends State<_SablierAnime> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c
        ..stop()
        ..value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // Retournement sur les 25 derniers % du cycle, pause le reste.
        final rotation = t < 0.75 ? 0.0 : Curves.easeInOut.transform((t - 0.75) / 0.25) * 0.5;
        final halo = 0.5 + 0.5 * (1 - (2 * t - 1).abs());
        return Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CouleursTaama.or.withValues(alpha: 0.12 + 0.08 * halo),
          ),
          child: Transform.rotate(
            angle: rotation * 2 * 3.141592653589793,
            child: const Icon(Icons.hourglass_top_rounded, color: CouleursTaama.or, size: 44),
          ),
        );
      },
    );
  }
}

/// Coche qui apparaît en rebond (une seule fois).
class _CocheApparition extends StatelessWidget {
  const _CocheApparition();

  @override
  Widget build(BuildContext context) {
    final reduit = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduit ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.green.shade600,
          boxShadow: [
            BoxShadow(color: Colors.green.withValues(alpha: 0.4), blurRadius: 20),
          ],
        ),
        child: const Icon(Icons.verified_rounded, color: Colors.white, size: 48),
      ),
    );
  }
}