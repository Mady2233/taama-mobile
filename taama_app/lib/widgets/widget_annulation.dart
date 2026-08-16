import 'package:flutter/material.dart';
import '../theme/couleurs_taama.dart';

/// Dialogue d'annulation avec choix du motif et affichage
/// de la pénalité éventuelle selon la politique Taama.
Future<Map<String, dynamic>?> afficherDialogueAnnulation(
  BuildContext context, {
  required DateTime dateCreation,
  required bool estChauffeur,
}) async {
  final minutes = DateTime.now().difference(dateCreation).inSeconds / 60;
  final estGratuit = minutes < 2;
  final penalite = estChauffeur ? 500 : 200;

  String? motifChoisi;

  final confirme = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text(
          'Annuler la course',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge pénalité
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: estGratuit
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: estGratuit ? Colors.green : Colors.red,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    estGratuit ? Icons.check_circle : Icons.warning,
                    color: estGratuit ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      estGratuit
                          ? 'Annulation gratuite\n(moins de 2 minutes)'
                          : 'Pénalité de $penalite FCFA\n'
                            '(${minutes.toStringAsFixed(1)} min écoulées)',
                      style: TextStyle(
                        color: estGratuit ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Motif de l\'annulation :',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            // Sélecteur de motif — codes alignés sur
            // Annulation.MOTIF_CHOICES_CLIENT / MOTIF_CHOICES_CONDUCTEUR
            // (trajets/models.py backend) : le backend compare en set exact,
            // sensible à la casse, donc ces codes doivent matcher au caractère
            // près, et la liste doit changer selon qui annule.
            ...(estChauffeur
                ? const {
                    'CLIENT_ABSENT': 'Client absent',
                    'ADRESSE_INTROUVABLE': 'Adresse introuvable',
                    'TROP_LOIN': 'Trop loin',
                    'PROBLEME_VEHICULE': 'Problème de véhicule',
                    'CLIENT_IRRESPECTUEUX': 'Client irrespectueux',
                    'AUTRE': 'Autre raison',
                  }
                : const {
                    'ATTENTE_TROP_LONGUE': 'Attente trop longue',
                    'CONDUCTEUR_INJOIGNABLE': 'Conducteur injoignable',
                    'ERREUR_ADRESSE': "Erreur d'adresse",
                    'PLUS_BESOIN': 'Plus besoin du trajet',
                    'PRIX_TROP_ELEVE': 'Prix trop élevé',
                    'CONDUCTEUR_NE_VIENT_PAS': 'Le conducteur ne vient pas',
                    'AUTRE': 'Autre raison',
                  }
            ).entries.map((entry) => RadioListTile<String>(
              title: Text(entry.value, style: const TextStyle(fontSize: 14)),
              value: entry.key,
              groupValue: motifChoisi,
              dense: true,
              activeColor: CouleursTaama.terreCuite,
              onChanged: (val) => setState(() => motifChoisi = val),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Garder la course'),
          ),
          ElevatedButton(
            onPressed: motifChoisi == null
                ? null
                : () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmer l\'annulation'),
          ),
        ],
      ),
    ),
  );

  if (confirme != true || motifChoisi == null) return null;
  return {'motif': motifChoisi};
}
