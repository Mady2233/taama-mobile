// Prix ajustable par le chauffeur : l'app ne fait que se déplacer entre les
// limites envoyées par le serveur, par pas, sans jamais les dépasser.
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/services/prix_ajustable.dart';

void main() {
  const limites = {'standard': 1450, 'min': 1250, 'max': 1650, 'pas': 100};

  group('lecture des limites du serveur', () {
    test('limites valides', () {
      final p = PrixAjustable.depuisJson(limites)!;
      expect((p.standard, p.min, p.max, p.pas), (1450, 1250, 1650, 100));
    });

    test('rien du serveur : ni − ni +', () {
      expect(PrixAjustable.depuisJson(null), isNull);
      expect(PrixAjustable.depuisJson('1450'), isNull);
    });

    test('limites incohérentes ou incomplètes : ignorées', () {
      expect(PrixAjustable.depuisJson({...limites, 'pas': 0}), isNull);
      expect(PrixAjustable.depuisJson({...limites, 'min': 1500}), isNull);
      expect(PrixAjustable.depuisJson({...limites, 'max': 1400}), isNull);
      expect(PrixAjustable.depuisJson({'standard': 1450, 'min': 1450, 'max': 1450, 'pas': 100}), isNull);
      expect(PrixAjustable.depuisJson({'standard': 1450, 'pas': 100}), isNull);
    });
  });

  group('− et +', () {
    final p = PrixAjustable.depuisJson(limites)!;

    test('par pas de 100 F', () {
      expect(p.monter(1450), 1550);
      expect(p.baisser(1450), 1350);
    });

    test('jamais au-delà des limites', () {
      expect(p.peutMonter(1650), isFalse);
      expect(p.monter(1650), 1650);
      expect(p.peutBaisser(1250), isFalse);
      expect(p.baisser(1250), 1250);
    });

    test('déjà au minimum du service : seulement +', () {
      final auMinimum = PrixAjustable.depuisJson({'standard': 500, 'min': 500, 'max': 600, 'pas': 100})!;
      expect(auMinimum.peutBaisser(500), isFalse);
      expect(auMinimum.peutMonter(500), isTrue);
    });
  });
}
