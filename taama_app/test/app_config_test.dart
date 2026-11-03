// AppConfig.applicationId : une seule valeur côté Dart, alignée sur Gradle,
// et utilisée comme User-Agent des tuiles. Même fichier dans taama_app et
// taama_conducteur (seuls les imports diffèrent).
import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taama_app/carte/fond_carte.dart';
import 'package:taama_app/config/app_config.dart';

void main() {
  test('applicationId identique à android/app/build.gradle.kts', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final id = RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle)?.group(1);
    expect(id, isNotNull, reason: 'applicationId introuvable dans build.gradle.kts');
    expect(AppConfig.applicationId, id);
  });

  test('versionName identique à « version: » du pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(pubspec)?.group(1);
    expect(version, isNotNull, reason: 'version: introuvable dans pubspec.yaml');
    expect(AppConfig.versionName, version);
  });

  test('User-Agent HTTP : Taama/<version> (<applicationId>; contact: <e-mail>)', () {
    expect(
      AppConfig.userAgentHttp,
      'Taama/${AppConfig.versionName} (${AppConfig.applicationId}; contact: ${AppConfig.contactSupport})',
    );
    expect(AppConfig.contactSupport, matches(RegExp(r'^[^@\s]+@[^@\s]+\.[a-z]{2,}$')));
  });

  test('tuiles : User-Agent « flutter_map (<applicationId>) »', () {
    final couche = coucheTuilesTaama(
      url: 'https://tuiles.exemple/{z}/{x}/{y}.png',
      client: MockClient((_) async => http.Response('', 404)),
      cache: const DisabledMapCachingProvider(),
    );
    expect(couche.tileProvider.headers['User-Agent'], 'flutter_map (${AppConfig.applicationId})');
  });
}
