// Suivi GPS (LocationService) : un arrêt demandé pendant le démarrage
// l'interrompt. « En ligne » : pendant les permissions ou la première position.
// Course : pendant la connexion du canal. Aucun flux GPS n'est ouvert après
// coup : sinon le service au premier plan et l'envoi des positions
// continuaient sans propriétaire (fin de session ou déconnexion).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:taama_conducteur/services/location_service.dart';

/// GPS factice : la première position attend [positionInitiale].
class _FauxGeolocator extends GeolocatorPlatform {
  final positionInitiale = Completer<Position>();
  int fluxOuverts = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async => LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async => LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) => positionInitiale.future;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    fluxOuverts++;
    return const Stream<Position>.empty();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FauxGeolocator gps;

  final connexionParDefaut = LocationService.connecterCanal;

  setUp(() {
    gps = _FauxGeolocator();
    GeolocatorPlatform.instance = gps;
  });

  tearDown(() => LocationService.connecterCanal = connexionParDefaut);

  test('arrêt pendant la première position : aucun flux GPS ouvert après coup', () async {
    final service = LocationService();
    final demarrage = service.demarrerSuiviPositionEnLigne();
    await Future<void>.delayed(Duration.zero);
    expect(service.enLigne, isTrue);
    await service.arreterSuiviPositionEnLigne(prevenirServeur: false);
    gps.positionInitiale.completeError(TimeoutException('GPS lent'));
    await demarrage;
    expect(gps.fluxOuverts, 0);
    expect(service.enLigne, isFalse);
  });

  test('course : arrêt pendant la connexion du canal, aucun flux GPS ouvert après coup', () async {
    final connexion = Completer<bool>();
    var connexions = 0;
    LocationService.connecterCanal = (_, __) {
      connexions++;
      return connexion.future;
    };
    final service = LocationService();
    final demarrage = service.demarrerEnvoiPosition('7');
    await Future<void>.delayed(Duration.zero);
    expect(connexions, 1);
    service.arreter();
    connexion.complete(false); // échec : une reconnexion aurait été planifiée
    await demarrage;
    expect(gps.fluxOuverts, 0);
  });

  test('course : sans arrêt, le flux GPS d’envoi s’ouvre', () async {
    LocationService.connecterCanal = (_, __) async => false;
    final service = LocationService();
    await service.demarrerEnvoiPosition('7');
    expect(gps.fluxOuverts, 1);
    service.arreter();
  });

  test('sans arrêt : le flux GPS s’ouvre', () async {
    final service = LocationService();
    final demarrage = service.demarrerSuiviPositionEnLigne();
    await Future<void>.delayed(Duration.zero);
    gps.positionInitiale.completeError(TimeoutException('GPS lent'));
    await demarrage;
    expect(gps.fluxOuverts, 1);
    expect(service.enLigne, isTrue);
    await service.arreterSuiviPositionEnLigne(prevenirServeur: false);
  });
}
