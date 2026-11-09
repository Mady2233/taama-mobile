// lib/screens/detail_course_screen.dart
//
// Détail d'une course de « Mes courses ». Présentationnel. Une valeur absente
// masque sa ligne ; commission et gain net seulement après un vrai paiement
// dans l'app (en espèces, Taama ne prélève rien).

import 'package:flutter/material.dart';

import '../models/course_historique.dart';
import '../theme/couleurs_taama.dart';
import '../utils/dates.dart';
import '../utils/format.dart';

class EcranDetailCourse extends StatelessWidget {
  const EcranDetailCourse({super.key, required this.course});

  final CourseHistorique course;

  @override
  Widget build(BuildContext context) {
    final c = course;
    final distance = c.distanceKm;
    final prix = c.prix;
    final annulateur = c.annuleePar == null
        ? null
        : (c.annuleePar == 'chauffeur' ? 'Toi' : 'Le client');

    return Scaffold(
      backgroundColor: CouleursTaama.sable,
      appBar: AppBar(
        title: const Text('Détail de la course'),
        backgroundColor: CouleursTaama.sable,
        foregroundColor: CouleursTaama.indigo,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(c.terminee ? 'Terminée' : 'Annulée'),
              backgroundColor: (c.terminee ? Colors.green : Colors.grey).withValues(alpha: 0.15),
              side: BorderSide.none,
            ),
          ),
          _Bloc(titre: 'Quand', lignes: [
            _Ligne('Commandée', dateHeureComplete(c.creeLe)),
            if (c.accepteLe != null) _Ligne('Acceptée', 'à ${heureMinute(c.accepteLe!)}'),
          ]),
          _Bloc(titre: 'Trajet', lignes: [
            if (c.quartierDepart != null) _Ligne('Départ', c.quartierDepart!),
            _Ligne('Destination', c.destination),
            if (distance != null && distance > 0) _Ligne('Distance', '${distance.toStringAsFixed(1).replaceAll('.', ',')} km'),
            if (c.categorie != null) _Ligne('Catégorie', c.categorie!),
            if (c.passager != null) _Ligne('Passager', c.passager!),
          ]),
          if (c.terminee)
            _Bloc(titre: 'Paiement', lignes: [
              if (prix != null) _Ligne('Prix payé par le client', formaterFcfa(prix)),
              if (c.prixStandard != null)
                _Ligne('Prix que tu as proposé', 'accepté par le client (prix standard : ${formaterFcfa(c.prixStandard!)})'),
              _Ligne('Mode', c.payeeDansLApp ? 'Portefeuille Taama' : 'Espèces, payé directement à toi'),
              if (c.payeeDansLApp && c.commission != null) _Ligne('Commission Taama', formaterFcfa(c.commission!)),
              if (c.payeeDansLApp && c.montantChauffeur != null) _Ligne('Ton gain', formaterFcfa(c.montantChauffeur!)),
            ]),
          if (c.terminee)
            _Bloc(titre: 'Note du client', lignes: [
              _Ligne('Note', c.noteRecue == null ? 'Pas encore notée' : '★ ${c.noteRecue}/5'),
            ]),
          if (c.annulee && (annulateur != null || c.motifAnnulation != null))
            _Bloc(titre: 'Annulation', lignes: [
              if (annulateur != null) _Ligne('Annulée par', annulateur),
              if (c.motifAnnulation != null) _Ligne('Motif', c.motifAnnulation!),
            ]),
        ],
      ),
    );
  }
}

class _Ligne {
  const _Ligne(this.libelle, this.valeur);
  final String libelle;
  final String valeur;
}

class _Bloc extends StatelessWidget {
  const _Bloc({required this.titre, required this.lignes});

  final String titre;
  final List<_Ligne> lignes;

  @override
  Widget build(BuildContext context) {
    if (lignes.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titre, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: CouleursTaama.indigo)),
            const SizedBox(height: 8),
            for (final l in lignes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(l.libelle, style: const TextStyle(color: CouleursTaama.grisTexte)),
                    ),
                    Expanded(child: Text(l.valeur, style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
