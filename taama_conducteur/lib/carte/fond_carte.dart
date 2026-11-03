// Fond de carte Taama : tuiles du fournisseur choisi au build (CarteConfig),
// cache disque, et « Carte indisponible » quand rien n'est configuré ou que
// le fournisseur refuse la clé. Fichier identique dans taama_app et
// taama_conducteur.
//
// À placer en PREMIER dans les children d'un FlutterMap :
//   FondCarteTaama(nuit: nuit, apercu: true),
//   CoucheCarteTaama(...), ... , AttributionCarteTaama(...)

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../config/carte_config.dart';
import '../widgets/couche_carte_taama.dart' show FondCarteIndisponible;

/// Refus du fournisseur de tuiles (clé invalide ou révoquée, quota épuisé,
/// application non autorisée) : partagé par toutes les cartes de l'app.
/// Dure jusqu'au prochain lancement : une clé refusée ne se répare pas
/// toute seule, et redemander chaque tuile gaspillerait les données.
class EtatFondCarte {
  EtatFondCarte._();

  static final ValueNotifier<bool> refuse = ValueNotifier(false);
  static int _refus = 0;

  /// Nombre de refus 401/403 avant de basculer : une tuile isolée en échec
  /// ne doit pas masquer toute la carte.
  static const int seuilRefus = 2;

  /// Branché sur errorTileCallback. Ne journalise RIEN : l'erreur contient
  /// l'adresse de la tuile, donc la clé du fournisseur. 404 (tuile absente)
  /// et 5xx (panne passagère) ne déclenchent rien.
  static void signaler(Object erreur) {
    if (erreur is! NetworkImageLoadException) return;
    if (erreur.statusCode != 401 && erreur.statusCode != 403) return;
    _refus++;
    if (_refus >= seuilRefus) refuse.value = true;
  }

  @visibleForTesting
  static void reinitialiser() {
    _refus = 0;
    refuse.value = false;
  }
}

/// Identifiant de cache d'une tuile : l'adresse SANS la clé du fournisseur.
/// La clé n'est ainsi jamais écrite sur le téléphone (noms de fichiers du
/// cache), et en changer ne force pas à retélécharger toutes les tuiles.
String adresseSansCle(String url) => url
    .replaceAllMapped(RegExp(r'([?&])key=[^&]*&?'), (m) => m[1]!)
    .replaceAll(RegExp(r'[?&]$'), '');

String cleCacheTuile(String url) =>
    BuiltInMapCachingProvider.uuidTileKeyGenerator(adresseSansCle(url));

/// Cache disque intégré de flutter_map (1 Go par défaut), plafonné pour les
/// petits téléphones. Une seule instance pour toute l'app.
/// [client] et [cache] : remplacés dans les tests seulement.
@visibleForTesting
NetworkTileProvider fournisseurTuiles({http.Client? client, MapCachingProvider? cache}) =>
    NetworkTileProvider(
      httpClient: client,
      // Une erreur HTTP n'est JAMAIS dessinée comme une tuile : certains
      // fournisseurs (MapTiler) joignent à leur 403 une image « Invalid key »
      // que flutter_map afficherait par défaut, sans jamais signaler
      // l'erreur — EtatFondCarte ne verrait rien. Ici, toute réponse non
      // 200 lève l'erreur, et deux 401/403 affichent « Carte indisponible ».
      attemptDecodeOfHttpErrorResponses: false,
      cachingProvider: cache ??
          BuiltInMapCachingProvider.getOrCreateInstance(
            maxCacheSize: 150 * 1024 * 1024,
            tileKeyGenerator: cleCacheTuile,
          ),
    );

/// La couche de tuiles de FondCarteTaama, câblée sur EtatFondCarte. Exposée
/// pour que les tests vérifient CE câblage-là, de bout en bout.
@visibleForTesting
TileLayer coucheTuilesTaama({
  required String url,
  bool apercu = false,
  http.Client? client,
  MapCachingProvider? cache,
}) =>
    TileLayer(
      urlTemplate: url,
      // En-tête envoyé : « flutter_map (<applicationId>) », exigé par les
      // politiques d'usage des serveurs de tuiles.
      userAgentPackageName: AppConfig.applicationId,
      tileProvider: fournisseurTuiles(client: client, cache: cache),
      maxNativeZoom: 19,
      panBuffer: apercu ? 0 : 1,
      errorTileCallback: (_, erreur, __) => EtatFondCarte.signaler(erreur),
    );

class FondCarteTaama extends StatelessWidget {
  const FondCarteTaama({super.key, this.nuit = false, this.apercu = false});

  final bool nuit;

  /// Carte non interactive (mini-carte) : aucune rangée de tuiles préchargée
  /// autour de la vue, puisqu'on ne peut pas la faire glisser.
  final bool apercu;

  @override
  Widget build(BuildContext context) {
    if (!CarteConfig.configuree) return FondCarteIndisponible(nuit: nuit);
    return ValueListenableBuilder<bool>(
      valueListenable: EtatFondCarte.refuse,
      builder: (context, refuse, _) => refuse
          ? FondCarteIndisponible(nuit: nuit)
          : coucheTuilesTaama(url: CarteConfig.tuiles(nuit: nuit), apercu: apercu),
    );
  }
}
