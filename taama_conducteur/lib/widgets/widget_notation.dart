import 'package:flutter/material.dart';
import '../theme/couleurs_taama.dart';

/// Affiche une boîte de dialogue de notation (1 à 5 étoiles) pour le
/// conducteur d'une course terminée et payée. [onEnvoyer] est appelé avec la
/// note choisie et le commentaire (peut être vide) quand l'utilisateur
/// valide ; l'utilisateur peut aussi ignorer la notation via "Passer".
Future<void> afficherDialogueNotation({
  required BuildContext context,
  required Future<void> Function(int note, String commentaire) onEnvoyer,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => _DialogueNotation(onEnvoyer: onEnvoyer),
  );
}

class _DialogueNotation extends StatefulWidget {
  final Future<void> Function(int note, String commentaire) onEnvoyer;

  const _DialogueNotation({required this.onEnvoyer});

  @override
  State<_DialogueNotation> createState() => _DialogueNotationState();
}

class _DialogueNotationState extends State<_DialogueNotation> {
  int _noteSelectionnee = 0;
  final TextEditingController _commentaireController = TextEditingController();
  bool _envoiEnCours = false;

  @override
  void dispose() {
    _commentaireController.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (_noteSelectionnee == 0) return;

    setState(() => _envoiEnCours = true);
    try {
      await widget.onEnvoyer(_noteSelectionnee, _commentaireController.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoiEnCours = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de l\'envoi de la note')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Noter votre conducteur', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final valeur = index + 1;
              final selectionnee = valeur <= _noteSelectionnee;
              return IconButton(
                onPressed: _envoiEnCours ? null : () => setState(() => _noteSelectionnee = valeur),
                icon: Icon(
                  selectionnee ? Icons.star : Icons.star_border,
                  color: CouleursTaama.or,
                  size: 32,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentaireController,
            enabled: !_envoiEnCours,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Un commentaire (optionnel)...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _envoiEnCours ? null : () => Navigator.pop(context),
          child: Text('Passer', style: TextStyle(color: Colors.grey.shade600)),
        ),
        ElevatedButton(
          onPressed: (_envoiEnCours || _noteSelectionnee == 0) ? null : _envoyer,
          style: ElevatedButton.styleFrom(
            backgroundColor: CouleursTaama.terreCuite,
            foregroundColor: Colors.white,
          ),
          child: _envoiEnCours
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Envoyer'),
        ),
      ],
    );
  }
}
