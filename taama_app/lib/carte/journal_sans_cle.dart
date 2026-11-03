// Journaux de l'app ET des bibliothèques (tout passe par debugPrint) :
// - en release : RIEN n'est écrit. debugPrint écrit dans logcat, lisible
//   hors de l'app ; la moindre ligne y exposerait position, token, photo… ;
// - en debug : écrits sans clé d'API ni token de session.
// Fichier identique dans taama_app et taama_conducteur.
import 'package:flutter/foundation.dart';

final RegExp _cle = RegExp(r'([?&](?:key|token)=)[^&\s]*');

/// « …png?key=ABC&lang=fr » devient « …png?key=***&lang=fr » ; idem token=.
String sansCle(String message) => message.replaceAllMapped(_cle, (m) => '${m[1]}***');

/// À appeler EN PREMIER dans main(). [silencieux] (vrai en release, réglable
/// pour les tests) : debugPrint ne fait plus rien du tout.
void installerJournalSansCle({bool silencieux = kReleaseMode}) {
  if (silencieux) {
    debugPrint = (String? message, {int? wrapWidth}) {};
    return;
  }
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) =>
      original(message == null ? null : sansCle(message), wrapWidth: wrapWidth);
}
