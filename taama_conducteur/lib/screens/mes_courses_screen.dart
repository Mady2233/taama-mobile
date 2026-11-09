// lib/screens/mes_courses_screen.dart
//
// « Mes courses » : courses terminées et annulées, regroupées par jour avec le
// total du jour (calculé par le serveur sur toute la journée). Présentationnel :
// données par paramètres, actions par callbacks (mes_courses_page.dart).

import 'package:flutter/material.dart';

import '../models/course_historique.dart';
import '../theme/couleurs_taama.dart';
import '../utils/dates.dart';
import '../utils/format.dart';

/// Clé d'un jour, au format des totaux du serveur (« 2026-11-09 »).
String cleJour(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class EcranMesCourses extends StatelessWidget {
  const EcranMesCourses({
    super.key,
    required this.courses,
    required this.totaux,
    required this.chargement,
    required this.chargementSuite,
    required this.aSuite,
    required this.onReessayer,
    required this.onActualiser,
    required this.onChargerSuite,
    required this.onOuvrir,
    this.erreur,
  });

  final List<CourseHistorique> courses;
  final Map<String, TotalJour> totaux;
  final bool chargement;
  final bool chargementSuite;
  final bool aSuite;
  final String? erreur;
  final VoidCallback onReessayer;
  final Future<void> Function() onActualiser;
  final VoidCallback onChargerSuite;
  final ValueChanged<CourseHistorique> onOuvrir;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      appBar: AppBar(
        title: const Text('Mes courses'),
        backgroundColor: CouleursTaama.sable,
        foregroundColor: CouleursTaama.indigo,
        elevation: 0,
      ),
      body: _contenu(),
    );
  }

  Widget _contenu() {
    if (courses.isEmpty && chargement) {
      return const Center(child: CircularProgressIndicator(color: CouleursTaama.terreCuite));
    }
    if (courses.isEmpty && erreur != null) {
      return _Message(
        icone: Icons.wifi_off_rounded,
        texte: erreur!,
        action: TextButton(onPressed: onReessayer, child: const Text('Réessayer')),
      );
    }
    if (courses.isEmpty) {
      return const _Message(
        icone: Icons.receipt_long_rounded,
        texte: 'Aucune course pour l’instant. Tes courses terminées et annulées apparaîtront ici.',
      );
    }

    final lignes = <Widget>[];
    String? jourCourant;
    for (final course in courses) {
      final jour = cleJour(course.creeLe);
      if (jour != jourCourant) {
        jourCourant = jour;
        lignes.add(_EnTeteJour(jour: course.creeLe, total: totaux[jour]));
      }
      lignes.add(_LigneCourse(course: course, onTap: () => onOuvrir(course)));
    }
    if (aSuite) {
      lignes.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: OutlinedButton(
          onPressed: chargementSuite ? null : onChargerSuite,
          child: chargementSuite
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Voir les courses plus anciennes'),
        ),
      ));
    }
    return RefreshIndicator(
      onRefresh: onActualiser,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: lignes),
    );
  }
}

class _EnTeteJour extends StatelessWidget {
  const _EnTeteJour({required this.jour, this.total});

  final DateTime jour;
  final TotalJour? total;

  @override
  Widget build(BuildContext context) {
    final t = total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              libelleJour(jour),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: CouleursTaama.indigo),
            ),
          ),
          if (t != null && t.courses > 0)
            Text(
              '${t.courses} course${t.courses > 1 ? 's' : ''} · ${formaterFcfa(t.total)}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: CouleursTaama.grisTexte),
            ),
        ],
      ),
    );
  }
}

class _LigneCourse extends StatelessWidget {
  const _LigneCourse({required this.course, required this.onTap});

  final CourseHistorique course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trajet = [course.quartierDepart, course.quartierDestination].whereType<String>().join(' → ');
    final sousTitre = [heureMinute(course.creeLe), if (trajet.isNotEmpty) trajet].join(' · ');
    final prix = course.prix;
    final etat = course.annulee
        ? (course.annuleePar == 'chauffeur' ? 'Annulée par toi' : 'Annulée par le client')
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: (course.terminee ? Colors.green : Colors.grey).withValues(alpha: 0.15),
          child: Icon(
            course.terminee ? Icons.check_rounded : Icons.close_rounded,
            color: course.terminee ? Colors.green.shade700 : Colors.grey.shade600,
          ),
        ),
        title: Text(course.destination, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(etat == null ? sousTitre : '$sousTitre\n$etat', maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (course.terminee && prix != null)
              Text(formaterFcfa(prix), style: const TextStyle(fontWeight: FontWeight.w800, color: CouleursTaama.indigo)),
            const Icon(Icons.chevron_right_rounded, color: CouleursTaama.grisTexte),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icone, required this.texte, this.action});

  final IconData icone;
  final String texte;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: CouleursTaama.grisTexte),
            const SizedBox(height: 12),
            Text(texte, textAlign: TextAlign.center, style: const TextStyle(color: CouleursTaama.grisTexte, fontSize: 15)),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
