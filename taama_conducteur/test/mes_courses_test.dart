// « Mes courses » : lecture de l'historique (rien d'inventé quand un champ
// manque), dates en français, et chaque état de l'écran (chargement, erreur,
// vide, liste par jour, détail).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_conducteur/models/course_historique.dart';
import 'package:taama_conducteur/screens/detail_course_screen.dart';
import 'package:taama_conducteur/screens/mes_courses_screen.dart';
import 'package:taama_conducteur/utils/dates.dart';
import 'package:taama_conducteur/utils/format.dart';

Map<String, dynamic> _brut({String statut = 'termine', String mode = 'especes', Map<String, dynamic>? extra}) => {
      'id': 7,
      'statut': statut,
      'cree_le': '2026-11-09T14:32:00+00:00',
      'accepte_le': '2026-11-09T14:33:00+00:00',
      'destination': 'ACI 2000',
      'distance_km': '5.2',
      'categorie': 'Berline',
      'depart_lat': 12.6392,
      'depart_lng': -8.0029,
      'destination_lat': null,
      'destination_lng': null,
      'prix': 1650,
      'mode_paiement': mode,
      'commission': null,
      'montant_chauffeur': null,
      'prix_ajuste': null,
      'passager': 'Awa',
      'note_recue': null,
      'annulation': null,
      ...?extra,
    };

void main() {
  group('lecture', () {
    test('course complète', () {
      final c = CourseHistorique.depuisJson(_brut())!;
      expect((c.id, c.terminee, c.prix, c.passager, c.distanceKm), (7, true, 1650, 'Awa', 5.2));
      expect(c.quartierDepart, isNotNull); // point de Bamako : un vrai quartier
      expect(c.quartierDestination, isNull); // position absente : aucun nom inventé
    });

    test('hors des quartiers connus : aucun nom', () {
      expect(quartierLePlusProche(14.0, -4.0), isNull);
    });

    test('entrée inexploitable : ignorée', () {
      expect(CourseHistorique.depuisJson({'statut': 'termine'}), isNull);
      expect(CourseHistorique.depuisJson('x'), isNull);
    });

    test('annulation et prix ajusté', () {
      final c = CourseHistorique.depuisJson(_brut(statut: 'annule', extra: {
        'annulation': {'par': 'client', 'motif': 'Plus besoin du trajet'},
        'prix_ajuste': {'propose': 1650, 'standard': 1450},
      }))!;
      expect((c.annulee, c.annuleePar, c.motifAnnulation, c.prixStandard), (true, 'client', 'Plus besoin du trajet', 1450));
    });
  });

  group('dates', () {
    final maintenant = DateTime(2026, 11, 9, 18);
    test('aujourd’hui, hier, puis le jour en toutes lettres', () {
      expect(libelleJour(DateTime(2026, 11, 9, 8), maintenant: maintenant), 'Aujourd’hui');
      expect(libelleJour(DateTime(2026, 11, 8, 23), maintenant: maintenant), 'Hier');
      expect(libelleJour(DateTime(2026, 11, 4), maintenant: maintenant), 'mercredi 4 novembre');
      expect(libelleJour(DateTime(2025, 12, 31), maintenant: maintenant), 'mercredi 31 décembre 2025');
    });
    test('heure', () => expect(heureMinute(DateTime(2026, 1, 1, 9, 5)), '09:05'));
  });

  group('liste', () {
    Future<List<String>> ouvrir(WidgetTester t, {
      List<CourseHistorique> courses = const [],
      bool chargement = false,
      String? erreur,
      bool aSuite = false,
      Map<String, TotalJour> totaux = const {},
    }) async {
      final actions = <String>[];
      await t.pumpWidget(MaterialApp(
        home: EcranMesCourses(
          courses: courses,
          totaux: totaux,
          chargement: chargement,
          chargementSuite: false,
          aSuite: aSuite,
          erreur: erreur,
          onReessayer: () => actions.add('reessayer'),
          onActualiser: () async => actions.add('actualiser'),
          onChargerSuite: () => actions.add('suite'),
          onOuvrir: (c) => actions.add('ouvrir ${c.id}'),
        ),
      ));
      return actions;
    }

    testWidgets('chargement', (t) async {
      await ouvrir(t, chargement: true);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('erreur : message et Réessayer', (t) async {
      final actions = await ouvrir(t, erreur: 'Impossible de charger tes courses.');
      await t.tap(find.text('Réessayer'));
      expect(actions, ['reessayer']);
    });

    testWidgets('aucune course : un message, jamais un écran vide', (t) async {
      await ouvrir(t);
      expect(find.textContaining('Aucune course pour l’instant'), findsOneWidget);
    });

    testWidgets('par jour, avec le total du serveur, et détail au toucher', (t) async {
      final course = CourseHistorique.depuisJson(_brut())!;
      final actions = await ouvrir(t, courses: [course], aSuite: true, totaux: {
        cleJour(course.creeLe): const TotalJour(3, 4500),
      });
      expect(find.text('3 courses · ${formaterFcfa(4500)}'), findsOneWidget);
      expect(find.text('Voir les courses plus anciennes'), findsOneWidget);
      await t.tap(find.text('ACI 2000'));
      await t.tap(find.text('Voir les courses plus anciennes'));
      expect(actions, ['ouvrir 7', 'suite']);
    });
  });

  group('détail', () {
    Future<void> ouvrir(WidgetTester t, CourseHistorique c) async {
      // Écran haut : tous les blocs construits (la liste ne bâtit pas ce qui est hors champ).
      await t.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(home: EcranDetailCourse(course: c)));
    }

    testWidgets('espèces : aucune commission inventée', (t) async {
      await ouvrir(t, CourseHistorique.depuisJson(_brut())!);
      expect(find.text('Espèces, payé directement à toi'), findsOneWidget);
      expect(find.text('Commission Taama'), findsNothing);
      expect(find.text('Pas encore notée'), findsOneWidget);
    });

    testWidgets('payée dans l’app : commission et gain réels', (t) async {
      await ouvrir(t, CourseHistorique.depuisJson(_brut(mode: 'portefeuille', extra: {
        'commission': 165, 'montant_chauffeur': 1485, 'note_recue': 5,
      }))!);
      expect(find.text(formaterFcfa(165)), findsOneWidget);
      expect(find.text(formaterFcfa(1485)), findsOneWidget);
      expect(find.text('★ 5/5'), findsOneWidget);
    });

    testWidgets('annulée : qui et pourquoi, pas de paiement', (t) async {
      await ouvrir(t, CourseHistorique.depuisJson(_brut(statut: 'annule', extra: {
        'annulation': {'par': 'chauffeur', 'motif': 'Client absent'},
      }))!);
      expect(find.text('Toi'), findsOneWidget);
      expect(find.text('Client absent'), findsOneWidget);
      expect(find.text('Paiement'), findsNothing);
    });
  });
}
