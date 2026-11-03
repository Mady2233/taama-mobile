// installerJournalSansCle : en release (silencieux) debugPrint n'écrit RIEN ;
// en debug, ni clé d'API ni token de session. Même fichier dans taama_app et
// taama_conducteur (seuls les imports diffèrent).
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/carte/journal_sans_cle.dart';

void main() {
  late DebugPrintCallback original;
  late List<String> journal;

  setUp(() {
    original = debugPrint;
    journal = [];
    debugPrint = (m, {wrapWidth}) => journal.add(m ?? '');
  });
  tearDown(() => debugPrint = original);

  test('release (silencieux) : aucune ligne écrite, même une donnée perso', () {
    installerJournalSansCle(silencieux: true);
    debugPrint('[LocationService] Position poussée : 12.6392, -8.0029');
    debugPrint('wss://x/ws/chat/demande_1/?token=abc123');
    debugPrint(null);
    expect(journal, isEmpty);
  });

  test('debug : token et clé masqués, le reste du message conservé', () {
    installerJournalSansCle(silencieux: false);
    debugPrint('WebSocket wss://x/ws/chat/demande_1/?token=abc123');
    debugPrint('https://t/1.png?lang=fr&key=SECRET&token=T0K&v=2');
    debugPrint('aucune donnée sensible');
    expect(journal, [
      'WebSocket wss://x/ws/chat/demande_1/?token=***',
      'https://t/1.png?lang=fr&key=***&token=***&v=2',
      'aucune donnée sensible',
    ]);
  });

  test('défaut = kReleaseMode : les tests tournent hors release, donc écrit', () {
    expect(kReleaseMode, isFalse);
    installerJournalSansCle();
    debugPrint('visible en debug');
    expect(journal, ['visible en debug']);
  });
}
