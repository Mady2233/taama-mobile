// lib/screens/mes_courses_page.dart
//
// Logique de « Mes courses » : 20 courses par page, chargées à la demande
// (« Voir les courses plus anciennes »), actualisation en tirant la liste.

import 'package:flutter/material.dart';

import '../models/course_historique.dart';
import '../services/api_service.dart';
import 'detail_course_screen.dart';
import 'mes_courses_screen.dart';

const String _messageErreur = 'Impossible de charger tes courses. Vérifie ta connexion et réessaie.';

class PageMesCourses extends StatefulWidget {
  const PageMesCourses({super.key});

  @override
  State<PageMesCourses> createState() => _PageMesCoursesState();
}

class _PageMesCoursesState extends State<PageMesCourses> {
  List<CourseHistorique> _courses = const [];
  Map<String, TotalJour> _totaux = const {};
  int _page = 0;
  bool _aSuite = false;
  bool _chargement = true;
  bool _chargementSuite = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger(premiere: true);
  }

  Future<void> _charger({required bool premiere}) async {
    if (!premiere && (_chargementSuite || !_aSuite)) return;
    setState(() {
      if (premiere) {
        _chargement = true;
        _erreur = null;
      } else {
        _chargementSuite = true;
      }
    });
    try {
      final page = premiere ? 1 : _page + 1;
      final reponse = await ApiService.mesCourses(page: page);
      if (!mounted) return;
      final nouvelles = [
        for (final brut in (reponse['courses'] as List?) ?? const [])
          if (CourseHistorique.depuisJson(brut) case final CourseHistorique course) course,
      ];
      final totaux = <String, TotalJour>{
        for (final entree in ((reponse['jours'] as Map?) ?? const {}).entries)
          if (entree.value is Map)
            '${entree.key}': TotalJour(
              ((entree.value as Map)['courses'] as num?)?.toInt() ?? 0,
              ((entree.value as Map)['total'] as num?)?.toInt() ?? 0,
            ),
      };
      setState(() {
        _courses = premiere ? nouvelles : [..._courses, ...nouvelles];
        _totaux = premiere ? totaux : {..._totaux, ...totaux};
        _page = page;
        _aSuite = reponse['suivante'] == true;
        _erreur = null;
      });
    } catch (e) {
      debugPrint('[MesCourses] Chargement : ${e.runtimeType}');
      if (!mounted) return;
      if (premiere) {
        setState(() => _erreur = _messageErreur);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(_messageErreur)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _chargement = false;
          _chargementSuite = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => EcranMesCourses(
        courses: _courses,
        totaux: _totaux,
        chargement: _chargement,
        chargementSuite: _chargementSuite,
        aSuite: _aSuite,
        erreur: _erreur,
        onReessayer: () => _charger(premiere: true),
        onActualiser: () => _charger(premiere: true),
        onChargerSuite: () => _charger(premiere: false),
        onOuvrir: (course) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EcranDetailCourse(course: course)),
        ),
      );
}
