// Aucune clé d'API dans les journaux de l'app, y compris ceux des
// bibliothèques : flutter_map journalise (debugPrint) l'adresse complète
// d'une tuile en échec, clé comprise — et debugPrint écrit aussi en release
// (logcat). Fichier identique dans taama_app et taama_conducteur.

import 'package:flutter/foundation.dart';

final RegExp _cle = RegExp(r'([?&]key=)[^&\s]*');

/// « …png?key=ABC&lang=fr » devient « …png?key=***&lang=fr ».
String sansCle(String message) => message.replaceAllMapped(_cle, (m) => '${m[1]}***');

/// À appeler EN PREMIER dans main() : tout ce qui passe ensuite par
/// debugPrint (app et bibliothèques) est écrit sans clé.
void installerJournalSansCle() {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) =>
      original(message == null ? null : sansCle(message), wrapWidth: wrapWidth);
}
