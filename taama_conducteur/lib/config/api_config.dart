class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://192.168.43.103:8000/api',
  );

  static String get wsUrl {
    final sansApi = baseUrl.endsWith('/api')
        ? baseUrl.substring(0, baseUrl.length - '/api'.length)
        : baseUrl;
    if (sansApi.startsWith('https://')) return 'wss://${sansApi.substring(8)}';
    if (sansApi.startsWith('http://')) return 'ws://${sansApi.substring(7)}';
    return sansApi;
  }
}
