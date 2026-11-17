import 'package:flutter/material.dart';
import '../models/service_course.dart';
import '../theme/couleurs_taama.dart';
import '../theme/taama_theme.dart';
import '../utils/format.dart';

/// Feuille « Choisis ta catégorie » : les services (catalogue TypeService)
/// avec leur devis figé côté serveur, AVANT que le client confirme. Aucun
/// prix calculé ici : chaque carte affiche exactement le `prix`/`devisId`
/// reçus de POST /trajets/estimer/ (voir ApiService.estimerCourse), et le
/// choix renvoie ce devis tel quel.
///
/// Le client touche une carte (elle s'entoure), puis « Continuer ». Un
/// service sans devis propose un repli au toucher.
///
/// [dureeTrajetMinutes] : durée du trajet (OSRM), pour « Dépose à 14h42 » et
/// l'arrivée estimée ; null : ces heures ne sont pas affichées, jamais
/// inventées. [horloge] : l'heure de référence (les tests la fixent).
Future<Map<String, dynamic>?> afficherChoixVehicule(
  BuildContext context, {
  required String destination,
  required double distanceKm,
  String? typePreselectionne,
  required List<ServiceCourse> services,
  String depart = 'Ma position',
  int? dureeTrajetMinutes,
  DateTime Function()? horloge,
}) async {
  // typePreselectionne ('Voiture'/'Moto', ex. depuis l'écran Services) filtre
  // la liste plutôt que de sauter le choix : le client voit toujours le prix
  // RÉEL avant de confirmer, jamais un choix auto-validé sur un devis qu'il
  // n'a pas vu. 'MOTO' est le seul type_vehicule qui vaut 'Moto' côté
  // backend (type_transport_associe) — tout le reste vaut 'Voiture'.
  final base = typePreselectionne == null
      ? services
      : services.where((s) =>
          (s.typeVehicule == 'MOTO') == (typePreselectionne == 'Moto')).toList();

  int parPrix(ServiceCourse a, ServiceCourse b) => (a.prix ?? 0).compareTo(b.prix ?? 0);
  final disponibles = base.where((s) => s.disponible && s.devisId != null).toList()..sort(parPrix);
  final sansChauffeur = base.where((s) => !s.disponible && s.devisId != null).toList()..sort(parPrix);
  final nonCommandables = base.where((s) => s.devisId == null).toList();
  final servicesTries = [...disponibles, ...sansChauffeur, ...nonCommandables];

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _FeuilleChoix(
      services: servicesTries,
      depart: depart,
      destination: destination,
      distanceKm: distanceKm,
      dureeTrajetMinutes: dureeTrajetMinutes,
      maintenant: (horloge ?? DateTime.now)(),
    ),
  );
}

/// « 3,2 km ».
String formaterKm(double km) => '${km.toStringAsFixed(1).replaceAll('.', ',')}\u00a0km';

/// « 14h42 ».
String formaterHeure(DateTime heure) =>
    '${heure.hour}h${heure.minute.toString().padLeft(2, '0')}';

/// Badges calculés sur la liste affichée, jamais inventés : « Le moins
/// cher » (prix le plus bas parmi les services commandables) et « Le plus
/// rapide » (attente la plus courte parmi ceux qui ont un chauffeur proche),
/// seulement s'il y a de quoi comparer et un seul gagnant.
({int? moinsCher, int? plusRapide}) badgesServices(List<ServiceCourse> services) {
  int? seulMinimum(List<ServiceCourse> candidats, int Function(ServiceCourse) valeur) {
    if (candidats.length < 2) return null;
    final minimum = candidats.map(valeur).reduce((a, b) => a < b ? a : b);
    final gagnants = candidats.where((s) => valeur(s) == minimum).toList();
    return gagnants.length == 1 ? gagnants.single.id : null;
  }

  return (
    moinsCher: seulMinimum(
      services.where((s) => s.devisId != null && s.prix != null).toList(),
      (s) => s.prix!,
    ),
    plusRapide: seulMinimum(
      services.where((s) => s.devisId != null && s.disponible && s.etaMinutes != null).toList(),
      (s) => s.etaMinutes!,
    ),
  );
}

/// Illustration du véhicule (vue de côté), selon le type du service.
String imageVehicule(String typeVehicule) => switch (typeVehicule) {
      'MOTO' => 'assets/vehicules/vehicule_moto.png',
      '4X4' => 'assets/vehicules/vehicule_suv.png',
      'TRICYCLE' => 'assets/vehicules/vehicule_tricycle.png',
      _ => 'assets/vehicules/vehicule_berline.png',
    };

Map<String, dynamic> _choixDe(ServiceCourse s) => {
      'type_service': s.id,
      'devis_id': s.devisId,
      'prix_estime': s.prix,
      'temps_minutes': s.etaMinutes,
      'disponible': s.disponible,
    };

class _FeuilleChoix extends StatefulWidget {
  const _FeuilleChoix({
    required this.services,
    required this.depart,
    required this.destination,
    required this.distanceKm,
    required this.dureeTrajetMinutes,
    required this.maintenant,
  });

  final List<ServiceCourse> services;
  final String depart;
  final String destination;
  final double distanceKm;
  final int? dureeTrajetMinutes;
  final DateTime maintenant;

  @override
  State<_FeuilleChoix> createState() => _FeuilleChoixState();
}

class _FeuilleChoixState extends State<_FeuilleChoix> {
  /// Le premier service commandable est choisi d'avance (le moins cher avec
  /// un chauffeur proche, sinon le moins cher) : un seul geste suffit.
  late ServiceCourse? _choisi =
      widget.services.where((s) => s.devisId != null).firstOrNull;

  void _toucher(ServiceCourse service) {
    if (service.devisId != null) {
      setState(() => _choisi = service);
      return;
    }
    // Non commandable : propose un repli plutôt que de laisser le client
    // face à une carte grisée sans issue.
    final repli = trouverStandardDeRepli(widget.services);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => repli != null
          ? AlertDialog(
              title: Text('${service.nom} indisponible'),
              content: Text(
                'Le service ${service.nom} n\'est pas encore proposé.\n\n'
                'Commander ${repli.nom} à ${formaterFcfaApi(repli.prix) ?? '—'} à la place ?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Ferme d'abord le dialog (son propre context), PUIS la
                    // feuille — jamais l'inverse.
                    Navigator.pop(dialogContext);
                    Navigator.pop(context, _choixDe(repli));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CouleursTaama.terreCuite,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Commander'),
                ),
              ],
            )
          : AlertDialog(
              title: const Text('Indisponible'),
              content: const Text('Ce service n\'est pas encore proposé.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final reference = services.where((s) => s.devisId != null).firstOrNull;
    final majoration = reference?.detail?['raison_majoration'] as String?;
    final badges = badgesServices(services);
    final choisi = _choisi;

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      decoration: const BoxDecoration(
        color: TaamaColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                  color: TaamaColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _EnTeteTrajet(
                      depart: widget.depart,
                      destination: widget.destination,
                      distanceKm: widget.distanceKm,
                      dureeTrajetMinutes: widget.dureeTrajetMinutes,
                      maintenant: widget.maintenant,
                    ),
                    if (majoration != null) ...[
                      const SizedBox(height: 10),
                      _BandeauMajoration(raison: majoration),
                    ],
                    const SizedBox(height: 18),
                    Text('Choisis ta catégorie', style: TaamaText.title.copyWith(fontSize: 20)),
                    const SizedBox(height: 12),
                    if (services.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Aucun service disponible pour ce trajet pour le moment.',
                          textAlign: TextAlign.center,
                          style: TaamaText.muted,
                        ),
                      )
                    else
                      for (final service in services) ...[
                        _CarteService(
                          service: service,
                          choisi: identical(service, choisi),
                          moinsCher: badges.moinsCher == service.id,
                          plusRapide: badges.plusRapide == service.id,
                          depose: widget.dureeTrajetMinutes != null && service.etaMinutes != null
                              ? widget.maintenant.add(Duration(
                                  minutes: service.etaMinutes! + widget.dureeTrajetMinutes!))
                              : null,
                          onTap: () => _toucher(service),
                        ),
                        const SizedBox(height: 10),
                      ],
                    if (reference?.detail != null)
                      Center(
                        child: TextButton.icon(
                          onPressed: () => _afficherDetailPrix(context, reference!.detail!),
                          icon: const Icon(Icons.info_outline, size: 15),
                          label: const Text('Comment est calculé le prix ?'),
                          style: TextButton.styleFrom(
                            foregroundColor: TaamaColors.textSecondary,
                            textStyle: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (choisi != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _choixDe(choisi)),
                  style: FilledButton.styleFrom(
                    backgroundColor: TaamaColors.primary,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(TaamaRadius.lg),
                    ),
                  ),
                  child: Text(
                    'Continuer avec ${choisi.nom}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TaamaText.body.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// « Ma position → Grand Marché », puis l'arrivée estimée (si la durée du
/// trajet est connue) et la distance.
class _EnTeteTrajet extends StatelessWidget {
  const _EnTeteTrajet({
    required this.depart,
    required this.destination,
    required this.distanceKm,
    required this.dureeTrajetMinutes,
    required this.maintenant,
  });

  final String depart;
  final String destination;
  final double distanceKm;
  final int? dureeTrajetMinutes;
  final DateTime maintenant;

  @override
  Widget build(BuildContext context) {
    final km = formaterKm(distanceKm);
    final duree = dureeTrajetMinutes;
    final detail = duree == null
        ? km
        : 'Arrivée estimée : ${formaterHeure(maintenant.add(Duration(minutes: duree)))}'
            ' · $duree\u00a0min ($km)';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: TaamaColors.surface,
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        boxShadow: TaamaShadows.card,
      ),
      child: Row(
        children: [
          // Départ (rond) relié à la destination (carré), comme le tracé.
          const Column(
            children: [
              Icon(Icons.circle, size: 10, color: TaamaColors.primary),
              SizedBox(height: 2, child: VerticalDivider(width: 2, color: TaamaColors.primary)),
              SizedBox(width: 2, height: 14, child: ColoredBox(color: TaamaColors.primary)),
              Icon(Icons.stop_rounded, size: 14, color: TaamaColors.navy),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: depart),
                    const TextSpan(text: '  →  ', style: TextStyle(color: TaamaColors.primary)),
                    TextSpan(text: destination),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TaamaText.body.copyWith(fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(detail, style: TaamaText.muted.copyWith(fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BandeauMajoration extends StatelessWidget {
  const _BandeauMajoration({required this.raison});

  final String raison;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: TaamaColors.warningSoft,
        borderRadius: BorderRadius.circular(TaamaRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time_rounded, color: TaamaColors.warning, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$raison — tarif majoré',
              style: TaamaText.body.copyWith(
                color: TaamaColors.warning,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une catégorie : illustration du véhicule, nom et places, attente et heure
/// de dépose, description, badges, prix. Toujours touchable, même sans devis
/// (le toucher propose alors un repli).
class _CarteService extends StatelessWidget {
  const _CarteService({
    required this.service,
    required this.choisi,
    required this.moinsCher,
    required this.plusRapide,
    required this.depose,
    required this.onTap,
  });

  final ServiceCourse service;
  final bool choisi;
  final bool moinsCher;
  final bool plusRapide;
  final DateTime? depose;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final commandable = service.devisId != null;
    final eta = service.etaMinutes;
    final ligneAttente = !commandable
        ? null
        : service.disponible && eta != null
            ? [
                '$eta\u00a0min d’attente',
                if (depose != null) 'Dépose à ${formaterHeure(depose!)}',
              ].join(' · ')
            : 'Recherche à la commande';
    final badges = [
      if (plusRapide) const _Badge('Le plus rapide', TaamaColors.success, TaamaColors.successSoft),
      if (moinsCher) const _Badge('Le moins cher', TaamaColors.primary, TaamaColors.primarySoft),
      if (service.necessiteClimatisation)
        const _Badge('Climatisé', TaamaColors.warning, TaamaColors.warningSoft, icone: Icons.ac_unit),
    ];

    final carte = Material(
      color: TaamaColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        side: BorderSide(
          color: choisi ? TaamaColors.primary : TaamaColors.border,
          width: choisi ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(TaamaRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
            children: [
              Container(
                width: 76,
                height: 60,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: choisi ? TaamaColors.primarySoft : TaamaColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(TaamaRadius.md),
                ),
                // Les illustrations ont de larges marges transparentes : on
                // les agrandit dans leur cadre.
                child: Transform.scale(
                  scale: 1.45,
                  child: Image.asset(
                  imageVehicule(service.typeVehicule),
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  // Image absente (test, asset retiré) : l'icône du type.
                  errorBuilder: (_, __, ___) => Icon(
                    service.typeVehicule == 'MOTO' ? Icons.two_wheeler : Icons.directions_car,
                    color: TaamaColors.navy,
                  ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            service.nom,
                            overflow: TextOverflow.ellipsis,
                            style: TaamaText.body.copyWith(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (service.placesMax > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.person_outline_rounded, size: 15, color: TaamaColors.textSecondary),
                          Text(
                            '${service.placesMax}',
                            semanticsLabel: '${service.placesMax} places',
                            textScaler: TextScaler.noScaling,
                            style: TaamaText.muted.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ],
                    ),
                    if (ligneAttente != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        ligneAttente,
                        style: TaamaText.body.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: service.disponible ? TaamaColors.success : TaamaColors.textSecondary,
                        ),
                      ),
                    ],
                    if (service.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        service.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TaamaText.muted.copyWith(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              commandable && service.prix != null
                  // Largeur plafonnée : en grand texte, le prix rétrécit au
                  // lieu de pousser le nom hors de la carte.
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 104),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formaterFcfa(service.prix!),
                              style: TaamaText.title.copyWith(fontSize: 18, color: TaamaColors.navy),
                            ),
                            Text('prix annoncé', style: TaamaText.muted.copyWith(fontSize: 11)),
                          ],
                        ),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: TaamaColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Indisponible',
                        style: TaamaText.muted.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
            ],
          ),
          // Badges sur leur propre ligne, sous les textes : toute la largeur
          // de la carte, même en grand texte.
          if (badges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 88, top: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: badges),
            ),
            ],
          ),
        ),
      ),
    );

    // Non commandable : opacité réduite, mais toujours touchable (repli).
    return Semantics(
      selected: choisi,
      child: commandable ? carte : Opacity(opacity: 0.5, child: carte),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.texte, this.couleur, this.fond, {this.icone});

  final String texte;
  final Color couleur;
  final Color fond;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(TaamaRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 11, color: couleur),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              texte,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: couleur),
            ),
          ),
        ],
      ),
    );
  }
}

/// Détail tel que renvoyé par calculer_prix_service (backend) : pas de
/// ventilation base/distance/temps (ce moteur n'a pas de terme temps,
/// contrairement à l'ancien calculer_prix) — seuls distance, majoration
/// éventuelle et prix final sont disponibles. Jamais de ligne inventée pour
/// combler l'absence d'un sous-total que le serveur ne fournit pas.
void _afficherDetailPrix(BuildContext context, Map<String, dynamic> detail) {
  final raisonMajoration = detail['raison_majoration'] as String?;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: const Text(
        'Détail du prix 🚗',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LignePrix('Distance', '${detail['distance_km']} km'),
            if (raisonMajoration != null)
              _LignePrix(
                raisonMajoration,
                '×${detail['coefficient']}',
                couleur: Colors.orange,
              ),
            const Divider(),
            _LignePrix(
              'TOTAL',
              formaterFcfaApi(detail['prix_final']) ?? '—',
              gras: true,
              couleur: CouleursTaama.terreCuite,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

class _LignePrix extends StatelessWidget {
  final String label;
  final String valeur;
  final bool gras;
  final Color? couleur;

  const _LignePrix(this.label, this.valeur, {this.gras = false, this.couleur});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: gras ? FontWeight.bold : FontWeight.normal,
              color: couleur,
            ),
          ),
          Text(
            valeur,
            style: TextStyle(
              fontWeight: gras ? FontWeight.bold : FontWeight.normal,
              color: couleur ?? CouleursTaama.indigo,
            ),
          ),
        ],
      ),
    );
  }
}
