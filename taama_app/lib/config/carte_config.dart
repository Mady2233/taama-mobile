/// Fond de carte : TOUT vient du build, aucune adresse n'est écrite dans le
/// code. Fichier identique dans taama_app et taama_conducteur.
///
///   flutter build … \
///     --dart-define=MAP_TILES_LIGHT=https://…/{z}/{x}/{y}.png?key=… \
///     --dart-define=MAP_TILES_DARK=https://…/{z}/{x}/{y}.png?key=… \
///     --dart-define="CARTE_ATTRIBUTION=© MapTiler © OpenStreetMap contributors" \
///     --dart-define=CARTE_REPERES_FOND=pharmacie,banque
///
/// Sans adresse de tuiles : aucune requête, la carte affiche « Carte
/// indisponible pour le moment ». Une release sans ces valeurs est refusée
/// par android/app/build.gradle.kts. Voir CONTEXTE.md §4.1.
class CarteConfig {
  CarteConfig._();

  static const String tuilesJour = String.fromEnvironment('MAP_TILES_LIGHT');
  static const String tuilesNuit = String.fromEnvironment('MAP_TILES_DARK');

  /// Mention exigée par le fournisseur du fond. Par défaut, la mention
  /// minimale, toujours due pour un fond construit sur OpenStreetMap.
  static const String attribution = String.fromEnvironment(
    'CARTE_ATTRIBUTION',
    defaultValue: '© OpenStreetMap contributors',
  );

  /// Catégories de repères que le fond dessine déjà, séparées par des
  /// virgules (noms de CategorieRepere : pharmacie, banque…). La couche de
  /// repères Taama ne les répète pas.
  static const String reperesDuFond = String.fromEnvironment('CARTE_REPERES_FOND');

  static String tuiles({required bool nuit}) => nuit ? tuilesNuit : tuilesJour;

  static bool get configuree => tuilesJour.isNotEmpty && tuilesNuit.isNotEmpty;
}
