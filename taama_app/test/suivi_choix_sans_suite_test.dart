// Demande ciblée sans suite : issue lue dans la réponse du serveur, message
// au client selon l'issue.
import 'package:flutter_test/flutter_test.dart';
import 'package:taama_app/screens/course/suivi_course_page.dart';

void main() {
  test('issue lue seulement sur une demande ciblée close', () {
    expect(issueChoixCiblee({'statut': 'annule', 'choix_chauffeur': null}), isNull);
    expect(issueChoixCiblee({'statut': 'annule'}), isNull);
    expect(issueChoixCiblee({'choix_chauffeur': {'issue': null}}), isNull);
    expect(issueChoixCiblee({'choix_chauffeur': {'issue': 'refusee'}}), 'refusee');
    expect(issueChoixCiblee({'choix_chauffeur': 'refusee'}), isNull);
  });

  test('un message par issue, avec le nom du chauffeur choisi', () {
    expect(messageChoixSansSuite('refusee', 'Seydou K.'), 'Seydou K. a refusé ta course. Choisis un autre chauffeur.');
    expect(messageChoixSansSuite('sans_reponse', 'Seydou K.'), 'Seydou K. n’a pas répondu. Choisis un autre chauffeur.');
    expect(messageChoixSansSuite('indisponible', 'Seydou K.'), 'Seydou K. n’est plus disponible. Choisis un autre chauffeur.');
    // C'est le client qui a refusé le prix proposé : rien à lui apprendre.
    expect(messageChoixSansSuite('prix_non_retenu', 'Seydou K.'), isNull);
  });

  test('nom inconnu (course reprise depuis l’accueil) : « Le chauffeur choisi »', () {
    expect(messageChoixSansSuite('refusee', null), 'Le chauffeur choisi a refusé ta course. Choisis un autre chauffeur.');
    expect(messageChoixSansSuite('sans_reponse', '  '), 'Le chauffeur choisi n’a pas répondu. Choisis un autre chauffeur.');
  });
}
