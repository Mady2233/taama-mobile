import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chauffeur_proche.dart';
import 'chauffeurs_proches_repository.dart';
import 'couleurs_recherche.dart';
import 'recherche_chauffeur_controller.dart';
import 'widgets/panneau_chauffeurs.dart';
import 'widgets/radar_chauffeurs.dart';

/// Écran « Trouver un chauffeur » : radar en direct et choix manuel du
/// chauffeur par le client.
class RechercheChauffeurScreen extends StatefulWidget {
  const RechercheChauffeurScreen({
    super.key,
    required this.repository,
    required this.positionDepart,
    required this.onChauffeurChoisi,
    this.localiser,
    this.rayonM = 3000,
  }) : assert(rayonM > 0 && rayonM <= 5000);

  final ChauffeursProchesRepository repository;

  /// Point de prise en charge du client.
  final GeoPoint positionDepart;

  /// Appelé quand le client confirme son choix. Doit gérer ses propres
  /// erreurs (chauffeur plus disponible, réseau). Le rafraîchissement est
  /// suspendu pendant l'appel et reprend à son retour si l'écran est
  /// toujours affiché.
  final Future<void> Function(ChauffeurProche chauffeur) onChauffeurChoisi;

  /// Optionnel : relit la position GPS (bouton « Me localiser »).
  final Future<GeoPoint?> Function()? localiser;

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
    rayonDemande: widget.rayonM,
  );

  bool _choixEnCours = false;
  bool _localisationEnCours = false;

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
    try {
      await widget.onChauffeurChoisi(chauffeur);
    } finally {
      _choixEnCours = false;
      if (mounted) _controleur.demarrer();
    }
  }

  Future<void> _recentrer() async {
    if (_localisationEnCours) return;
    final localiser = widget.localiser;
    if (localiser == null) {
      _controleur.demarrer();
      return;
    }

    setState(() => _localisationEnCours = true);
    GeoPoint? position;
    try {
      position = await localiser();
    } catch (_) {
      position = null;
    } finally {
      if (mounted) setState(() => _localisationEnCours = false);
    }
    if (!mounted) return;

    if (position != null && position.estValide) {
      unawaited(_controleur.changerPosition(position));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Position introuvable. Activez la localisation puis réessayez.'),
        ),
      );
    }
  }

  void _selectionner(ChauffeurProche chauffeur) {
    unawaited(HapticFeedback.selectionClick());
    _controleur.selectionner(chauffeur);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CouleursRecherche.nuit,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(child: _FondCarte()),
            ListenableBuilder(
              listenable: _controleur,
              builder: (context, _) {
                final c = _controleur;
                final selection = c.selectionne;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _zoneRadar(c, selection)),
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
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoneRadar(RechercheChauffeurController c, ChauffeurProche? selection) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: _EnTete(
                rayonM: c.rayonM,
                chargement: c.chargementInitial,
                obsolete: c.estObsolete,
                filtre: c.filtre,
                nombreTous: c.nombre(),
                nombreVoitures: c.nombre(TypeVehicule.voiture),
                nombreMotos: c.nombre(TypeVehicule.moto),
                onFiltre: c.choisirFiltre,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, contraintes) {
                  // Le radar passe légèrement sous le panneau, comme sur la maquette.
                  const debord = 20.0;
                  final hauteur = contraintes.maxHeight + debord;
                  final cote = math.min(contraintes.maxWidth - 24, hauteur - 8);
                  if (cote < 120) return const SizedBox.shrink();
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: (contraintes.maxWidth - cote) / 2,
                        top: (hauteur - cote) / 2,
                        width: cote,
                        height: cote,
                        child: RadarChauffeurs(
                          chauffeurs: c.tous,
                          filtre: c.filtre,
                          selectionne: selection,
                          centre: c.centre,
                          rayonM: c.rayonM,
                          onSelection: _selectionner,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 12,
          child: _BoutonLocaliser(
            enCours: _localisationEnCours,
            onTap: _recentrer,
          ),
        ),
      ],
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({
    required this.rayonM,
    required this.chargement,
    required this.obsolete,
    required this.filtre,
    required this.nombreTous,
    required this.nombreVoitures,
    required this.nombreMotos,
    required this.onFiltre,
  });

  final int rayonM;
  final bool chargement;
  final bool obsolete;
  final TypeVehicule? filtre;
  final int nombreTous;
  final int nombreVoitures;
  final int nombreMotos;
  final ValueChanged<TypeVehicule?> onFiltre;

  @override
  Widget build(BuildContext context) {
    final rayon = formaterRayon(rayonM);
    final enAlerte = obsolete && !chargement;
    final statut = chargement
        ? 'Recherche · rayon $rayon'
        : enAlerte
            ? 'Connexion instable · nouvelle tentative'
            : 'En direct · rayon $rayon';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BoutonRond(
                icone: Icons.arrow_back_ios_new_rounded,
                libelle: 'Retour',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trouver un chauffeur',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _PointDirect(
                          couleur: enAlerte
                              ? CouleursRecherche.alerte
                              : CouleursRecherche.direct,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            statut,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xB3FFFFFF),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Filtre(
                  libelle: 'Tous',
                  nombre: nombreTous,
                  actif: filtre == null,
                  onTap: () => onFiltre(null),
                ),
                const SizedBox(width: 8),
                _Filtre(
                  libelle: 'Voitures',
                  nombre: nombreVoitures,
                  actif: filtre == TypeVehicule.voiture,
                  onTap: () => onFiltre(TypeVehicule.voiture),
                ),
                const SizedBox(width: 8),
                _Filtre(
                  libelle: 'Motos',
                  nombre: nombreMotos,
                  actif: filtre == TypeVehicule.moto,
                  onTap: () => onFiltre(TypeVehicule.moto),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Filtre extends StatelessWidget {
  const _Filtre({
    required this.libelle,
    required this.nombre,
    required this.actif,
    required this.onTap,
  });

  final String libelle;
  final int nombre;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: actif,
      label: '$libelle, $nombre',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            color: actif ? Colors.white : const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: actif ? Colors.white : const Color(0x26FFFFFF),
            ),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: libelle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: ' $nombre',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: actif
                        ? CouleursRecherche.texteDoux
                        : const Color(0x99FFFFFF),
                  ),
                ),
              ],
            ),
            style: TextStyle(
              fontSize: 15,
              color: actif ? CouleursRecherche.nuit : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _BoutonRond extends StatelessWidget {
  const _BoutonRond({
    required this.icone,
    required this.libelle,
    required this.onTap,
  });

  final IconData icone;
  final String libelle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: libelle,
      excludeSemantics: true,
      child: Material(
        color: const Color(0x1AFFFFFF),
        shape: const CircleBorder(side: BorderSide(color: Color(0x26FFFFFF))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 46,
            child: Icon(icone, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

class _BoutonLocaliser extends StatelessWidget {
  const _BoutonLocaliser({required this.enCours, required this.onTap});

  final bool enCours;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Me localiser',
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: const Color(0x66000000),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enCours ? null : onTap,
          child: SizedBox.square(
            dimension: 48,
            child: enCours
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.my_location_rounded,
                    color: CouleursRecherche.nuit,
                    size: 22,
                  ),
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
      duration: const Duration(milliseconds: 300),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: couleur,
        boxShadow: [BoxShadow(color: couleur.withAlpha(140), blurRadius: 6)],
      ),
    );
  }
}

/// Fond décoratif : dégradé bleu nuit, lueurs et trame discrète.
/// Ce n'est volontairement pas une carte (voir le brief).
class _FondCarte extends StatelessWidget {
  const _FondCarte();

  @override
  Widget build(BuildContext context) =>
      const RepaintBoundary(child: CustomPaint(painter: _PeintreFond()));
}

class _PeintreFond extends CustomPainter {
  const _PeintreFond();

  @override
  void paint(Canvas canvas, Size size) {
    final cadre = Offset.zero & size;
    canvas.drawRect(
      cadre,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2152), Color(0xFF12173A)],
        ).createShader(cadre),
    );

    void lueur(Offset centre, double rayon, Color couleur) {
      final zone = Rect.fromCircle(center: centre, radius: rayon);
      canvas.drawCircle(
        centre,
        rayon,
        Paint()
          ..shader = RadialGradient(colors: [couleur, couleur.withAlpha(0)])
              .createShader(zone),
      );
    }

    lueur(Offset(size.width * 0.85, size.height * 0.12), size.width * 0.45,
        const Color(0x2214B8A6));
    lueur(Offset(size.width * 0.1, size.height * 0.55), size.width * 0.5,
        const Color(0x225546E8));

    final trame = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = 1;
    const pas = 34.0;
    for (var x = pas; x < size.width; x += pas) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), trame);
    }
    for (var y = pas; y < size.height; y += pas) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), trame);
    }
  }

  @override
  bool shouldRepaint(covariant _PeintreFond ancien) => false;
}
