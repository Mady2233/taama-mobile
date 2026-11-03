/// Identité de l'app côté Dart. Seul fichier de lib/config/ qui diffère
/// entre taama_app et taama_conducteur.
class AppConfig {
  AppConfig._();

  /// Doit rester égal à applicationId (android/app/build.gradle.kts) :
  /// vérifié par test/app_config_test.dart.
  static const String applicationId = 'com.taama.taama_app';

  /// Doit rester égal à la partie avant « + » de « version: » du
  /// pubspec.yaml : vérifié par test/app_config_test.dart.
  static const String versionName = '1.0.0';

  /// Même adresse que TAAMA_CONTACT_SUPPORT côté serveur (politique de
  /// confidentialité).
  static const String contactSupport = 'nkakalanso@gmail.com';

  /// Adresse publique de la politique, déclarée dans la fiche Google Play : stable.
  static const String urlPolitiqueConfidentialite =
      'https://taama-backend-gt9i.onrender.com/politique-confidentialite/';

  /// User-Agent des appels HTTP vers des services tiers (Nominatim, OSRM) :
  /// leurs politiques d'usage exigent une app identifiable et joignable.
  static const String userAgentHttp =
      'Taama/$versionName ($applicationId; contact: $contactSupport)';
}
