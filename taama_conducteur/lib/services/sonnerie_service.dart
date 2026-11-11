import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show HapticFeedback;

/// Sonnerie d'une nouvelle demande de course (app ouverte ou en arrière-plan
/// récent). Sonne EN BOUCLE avec vibration jusqu'à [arreter] — appelé quand
/// le chauffeur accepte/refuse ou quand la demande disparaît — et se coupe
/// d'elle-même après [dureeMax] (jamais de sonnerie infinie si un appel
/// d'arrêt était manqué).
///
/// Singleton : une seule sonnerie à la fois, même si plusieurs demandes
/// arrivent ensemble ou si le polling et FCM signalent la même demande.
class SonnerieService {
  SonnerieService._();
  static final SonnerieService instance = SonnerieService._();

  static const Duration dureeMax = Duration(seconds: 45);
  static const String _fichier = 'sons/sonnerie_course.wav';

  AudioPlayer? _lecteur;
  Timer? _arretAuto;
  Timer? _vibration;
  bool _enCours = false;

  bool get enCours => _enCours;

  /// La vibration en boucle tourne.
  @visibleForTesting
  bool get vibre => _vibration != null;

  /// Remplace la lecture du son dans les tests (pas de lecteur natif).
  @visibleForTesting
  Future<void> Function()? lecturePourTest;

  Future<AudioPlayer> _preparerLecteur() async {
    final existant = _lecteur;
    if (existant != null) return existant;
    final lecteur = AudioPlayer(playerId: 'sonnerie_course');
    await lecteur.setReleaseMode(ReleaseMode.loop);
    await lecteur.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        // Flux « sonnerie » : suit le volume de sonnerie du téléphone,
        // comme un appel entrant.
        usageType: AndroidUsageType.notificationRingtone,
        contentType: AndroidContentType.sonification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        stayAwake: true,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.mixWithOthers},
      ),
    ));
    _lecteur = lecteur;
    return lecteur;
  }

  /// Démarre la sonnerie (sans effet si elle sonne déjà).
  Future<void> demarrer() async {
    if (_enCours) return;
    _enCours = true;
    try {
      final lecture = lecturePourTest;
      if (lecture != null) {
        await lecture();
      } else {
        final lecteur = await _preparerLecteur();
        if (!_enCours) return; // arrêtée pendant la préparation
        await lecteur.play(AssetSource(_fichier), volume: 1.0);
      }
    } catch (e) {
      // Pas de son (fichier absent, audio occupé…) : la vibration et
      // l'écran de demande restent — jamais de crash pour une sonnerie.
      if (kDebugMode) debugPrint('[Sonnerie] Lecture impossible : $e');
    }
    // Arrêtée pendant le lancement du son (demande disparue entre-temps) :
    // ni vibration ni arrêt automatique relancés — l'arrêt automatique ne
    // couperait plus rien — et le son, s'il est parti, est coupé.
    if (!_enCours) {
      try {
        await _lecteur?.stop();
      } catch (_) {
        // Rien à couper.
      }
      return;
    }
    HapticFeedback.heavyImpact();
    _vibration?.cancel();
    _vibration = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      HapticFeedback.heavyImpact();
    });
    _arretAuto?.cancel();
    _arretAuto = Timer(dureeMax, arreter);
  }

  /// Coupe la sonnerie (sans effet si elle ne sonne pas).
  Future<void> arreter() async {
    if (!_enCours) return;
    _enCours = false;
    _arretAuto?.cancel();
    _arretAuto = null;
    _vibration?.cancel();
    _vibration = null;
    try {
      await _lecteur?.stop();
    } catch (e) {
      if (kDebugMode) debugPrint('[Sonnerie] Arrêt impossible : $e');
    }
  }
}
