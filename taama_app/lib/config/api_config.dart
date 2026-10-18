class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://taama-backend-gt9i.onrender.com/api',
  );

  /// Racine du serveur, sans /api : pages publiques et /api/config-app/.
  static String get siteUrl => baseUrl.endsWith('/api')
      ? baseUrl.substring(0, baseUrl.length - '/api'.length)
      : baseUrl;

  static String get wsUrl {
    final sansApi = siteUrl;
    if (sansApi.startsWith('https://')) return 'wss://${sansApi.substring(8)}';
    if (sansApi.startsWith('http://')) return 'ws://${sansApi.substring(7)}';
    return sansApi;
  }
}
